"use strict";

const crypto = require("crypto");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const {
  getFirestore,
  FieldValue,
  Timestamp,
  FieldPath,
} = require("firebase-admin/firestore");

const {createCalendarClient, listEventsBetween} = require("./calendarClient");

const gcalServiceAccountKey = defineSecret("GCAL_SERVICE_ACCOUNT_KEY");

const db = getFirestore();

/**
 * @param {FirebaseFirestore.DocumentData|undefined} data
 * @return {string}
 */
function calendarIdFromCareGroupDoc(data) {
  const d = data || {};
  const gc = d.groupCalendar;
  if (gc && typeof gc === "object") {
    const id = gc.calendarId;
    if (id != null && String(id).trim()) {
      return String(id).trim();
    }
  }
  if (d.groupCalendarId != null && String(d.groupCalendarId).trim()) {
    return String(d.groupCalendarId).trim();
  }
  return "";
}

/**
 * Document id where tasks / linkedCalendarEvents live — matches Flutter
 * [CareGroupOption.dataCareGroupId]: use [careGroupId] field when set, else the doc id.
 * @param {string} teamOrMergedDocId
 * @param {FirebaseFirestore.DocumentData|undefined} data
 * @return {string}
 */
function dataCareGroupDocId(teamOrMergedDocId, data) {
  const d = data || {};
  const linked =
    d.careGroupId != null ? String(d.careGroupId).trim() : "";
  if (linked) {
    return linked;
  }
  return teamOrMergedDocId;
}

/**
 * @param {FirebaseFirestore.DocumentSnapshot} docSnap
 * @return {Promise<string>}
 */
async function resolveCalendarIdForCareGroupDoc(docSnap) {
  const d = docSnap.data() || {};
  let cid = calendarIdFromCareGroupDoc(d);
  if (cid) {
    return cid;
  }
  const linked =
    d.careGroupId != null ? String(d.careGroupId).trim() : "";
  if (linked) {
    const other = await db.collection("careGroups").doc(linked).get();
    if (other.exists) {
      cid = calendarIdFromCareGroupDoc(other.data());
    }
  }
  if (!cid) {
    const teamSnap = await db
      .collection("careGroups")
      .where("careGroupId", "==", docSnap.id)
      .limit(5)
      .get();
    for (const td of teamSnap.docs) {
      cid = calendarIdFromCareGroupDoc(td.data());
      if (cid) {
        break;
      }
    }
  }
  return cid || "";
}

/**
 * Stable Firestore document id derived from Google's event id.
 * @param {string} gcalEventId
 * @return {string}
 */
function docIdForGcalEvent(gcalEventId) {
  return (
    "g_" +
    crypto.createHash("sha256").update(String(gcalEventId)).digest("hex").slice(0, 40)
  );
}

/**
 * @param {string} ymd
 * @return {Date}
 */
function parseYmdUtcNoon(ymd) {
  const parts = String(ymd).split("-").map(Number);
  if (parts.length !== 3) {
    return new Date();
  }
  return new Date(Date.UTC(parts[0], parts[1] - 1, parts[2], 12, 0, 0));
}

/**
 * @param {import("googleapis").calendar_v3.Schema$Event} ev
 * @return {{allDay: boolean, startAt: Date, endAt: Date | null}|null}
 */
function parseEventStartEnd(ev) {
  const s = ev.start || {};
  const e = ev.end || {};
  if (s.date) {
    const startAt = parseYmdUtcNoon(s.date);
    return {allDay: true, startAt, endAt: null};
  }
  if (s.dateTime) {
    return {
      allDay: false,
      startAt: new Date(s.dateTime),
      endAt: e.dateTime ? new Date(e.dateTime) : null,
    };
  }
  return null;
}

/**
 * Emails Calendar API uses for rooms/resources — not inviting people here.
 * @param {string} email
 * @return {boolean}
 */
function isNonPersonCalendarEmail(email) {
  const e = String(email || "").toLowerCase();
  return (
    e.endsWith("@resource.calendar.google.com") ||
    e.endsWith("@group.calendar.google.com")
  );
}

/**
 * Organizer plus attendees from Google Calendar event metadata (deduped by email).
 * @param {import("googleapis").calendar_v3.Schema$Event} ev
 * @return {Array<{email: string, name: string | null, role: string}>}
 */
function peopleFromCalendarEvent(ev) {
  /** @type {Array<{email: string, name: string | null, role: string}>} */
  const out = [];

  /** @param {string|null|undefined} rawEmail @param {string|null|undefined} name @param {string} role */
  const push = (rawEmail, name, role) => {
    const raw = rawEmail != null ? String(rawEmail).trim().toLowerCase() : "";
    if (!raw || !raw.includes("@") || isNonPersonCalendarEmail(raw)) {
      return;
    }
    const nm =
      name != null && String(name).trim() ? String(name).trim() : null;
    out.push({
      email: raw,
      name: nm,
      role,
    });
  };

  const org = ev.organizer;
  if (org && org.email) {
    push(org.email, org.displayName, "organizer");
  }

  const attendees = ev.attendees;
  if (Array.isArray(attendees)) {
    for (const a of attendees) {
      if (!a || !a.email) continue;
      push(a.email, a.displayName, "participant");
    }
  }

  const seen = new Set();
  const dedup = [];
  for (const p of out) {
    if (seen.has(p.email)) {
      continue;
    }
    seen.add(p.email);
    dedup.push(p);
  }
  return dedup.length > 120 ? dedup.slice(0, 120) : dedup;
}

/**
 * @param {string} careGroupId
 * @return {Promise<Set<string>>}
 */
async function loadTaskGcalIdsToSkip(careGroupId) {
  const skip = new Set();
  const snap = await db
    .collection("careGroups")
    .doc(careGroupId)
    .collection("tasks")
    .get();
  snap.forEach((d) => {
    const g = d.get("gcalEventId");
    if (g != null && String(g).trim()) {
      skip.add(String(g).trim());
    }
  });
  return skip;
}

/**
 * @param {string} careGroupId Firestore doc id for shared data (tasks, linkedCalendarEvents).
 * @param {import("googleapis").calendar_v3.Calendar} calendar
 * @param {string} calendarIdResolved
 * @return {Promise<number>} number of events mirrored
 */
async function syncCareGroup(careGroupId, calendar, calendarIdResolved) {
  const now = new Date();
  const timeMin = new Date(now);
  timeMin.setDate(timeMin.getDate() - 14);
  const timeMax = new Date(now);
  timeMax.setDate(timeMax.getDate() + 180);

  const timeMinISO = timeMin.toISOString();
  const timeMaxISO = timeMax.toISOString();

  const rawEvents = await listEventsBetween(
    calendar,
    calendarIdResolved,
    timeMinISO,
    timeMaxISO,
  );
  const taskSkipIds = await loadTaskGcalIdsToSkip(careGroupId);
  const col = db.collection("careGroups").doc(careGroupId).collection(
    "linkedCalendarEvents",
  );

  const incomingDocs = [];

  for (const ev of rawEvents) {
    if (!ev.id || ev.status === "cancelled") {
      continue;
    }
    if (taskSkipIds.has(String(ev.id))) {
      continue;
    }
    const se = parseEventStartEnd(ev);
    if (!se) {
      continue;
    }
    const docId = docIdForGcalEvent(ev.id);
    const title =
      ev.summary && String(ev.summary).trim()
        ? String(ev.summary).trim()
        : "Event";
    const htmlLink =
      ev.htmlLink != null && String(ev.htmlLink).trim()
        ? String(ev.htmlLink).trim()
        : null;

    const calendarPeople = peopleFromCalendarEvent(ev);

    incomingDocs.push({
      docId,
      data: {
        gcalEventId: String(ev.id),
        title,
        startAt: Timestamp.fromDate(se.startAt),
        endAt: se.endAt ? Timestamp.fromDate(se.endAt) : null,
        allDay: !!se.allDay,
        htmlLink,
        calendarPeople,
        syncedAt: FieldValue.serverTimestamp(),
      },
    });
  }

  const incomingIds = new Set(incomingDocs.map((x) => x.docId));

  const existing = await col
    .where("startAt", ">=", Timestamp.fromDate(timeMin))
    .where("startAt", "<=", Timestamp.fromDate(timeMax))
    .get();

  const deletes = [];
  existing.forEach((doc) => {
    if (!incomingIds.has(doc.id)) {
      deletes.push(doc.ref);
    }
  });

  const maxBatch = 400;
  for (let i = 0; i < deletes.length; i += maxBatch) {
    const batch = db.batch();
    for (const ref of deletes.slice(i, i + maxBatch)) {
      batch.delete(ref);
    }
    await batch.commit();
  }

  for (let i = 0; i < incomingDocs.length; i += maxBatch) {
    const batch = db.batch();
    for (const row of incomingDocs.slice(i, i + maxBatch)) {
      batch.set(col.doc(row.docId), row.data, {merge: true});
    }
    await batch.commit();
  }
  return incomingDocs.length;
}

async function runSync() {
  const keyJson = gcalServiceAccountKey.value();
  if (!keyJson || !String(keyJson).trim()) {
    console.warn(
      "syncInboundGoogleCalendar: GCAL_SERVICE_ACCOUNT_KEY not configured",
    );
    return;
  }

  /** @type {FirebaseFirestore.QueryDocumentSnapshot | null} */
  let lastDoc = null;
  for (;;) {
    let query = db.collection("careGroups").orderBy(FieldPath.documentId()).limit(120);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snap = await query.get();
    if (snap.empty) {
      break;
    }
    for (const doc of snap.docs) {
      const teamOrMergedId = doc.id;
      const dataWriteId = dataCareGroupDocId(teamOrMergedId, doc.data());
      let cid = await resolveCalendarIdForCareGroupDoc(doc);
      // Do NOT apply legacy GCAL_CALENDAR_ID fallback: that mirrors one calendar into every
      // group's linkedCalendarEvents. Only sync when calendarId / groupCalendar is set on the
      // careGroup graph (resolver above).
      if (!cid) {
        continue;
      }
      let calendar;
      try {
        const c = createCalendarClient({
          keyJson: String(keyJson).trim(),
          calendarId: cid,
        });
        calendar = c.calendar;
      } catch (e) {
        console.error(
          "syncInboundGoogleCalendar: create client failed for " + teamOrMergedId,
          e,
        );
        continue;
      }
      try {
        const n = await syncCareGroup(dataWriteId, calendar, cid);
        console.log(
          "syncInboundGoogleCalendar: careGroup doc=" + teamOrMergedId +
          " dataDoc=" + dataWriteId + " calendarId=" + cid.slice(0, 32) +
          "… eventsWritten=" + n,
        );
      } catch (e) {
        console.error(
          "syncInboundGoogleCalendar: sync failed dataDoc=" + dataWriteId,
          e,
        );
      }
    }
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < 120) {
      break;
    }
  }
}

exports.syncInboundGoogleCalendar = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "us-central1",
    secrets: [gcalServiceAccountKey],
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    await runSync();
  },
);
