"use strict";

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const {buildEvent} = require("./eventBuilder");
const {
  createCalendarClient,
  deleteEvent,
  insertEvent,
  updateEvent,
} = require("./calendarClient");

const gcalServiceAccountKey = defineSecret("GCAL_SERVICE_ACCOUNT_KEY");
const gcalCalendarId = defineSecret("GCAL_CALENDAR_ID");

const db = getFirestore();

const SYNC_FIELD_KEYS = [
  "title",
  "notes",
  "status",
  "dueAt",
  "dueCalendarDate",
  "dueTime",
  "dueDate",
  "assignedTo",
  "durationMinutes",
  "description",
];

/**
 * @param {FirebaseFirestore.DocumentSnapshot|undefined} before
 * @param {FirebaseFirestore.DocumentSnapshot|undefined} after
 * @return {boolean}
 */
function onlySystemGcalWrite(before, after) {
  if (!before || !after || !before.exists || !after.exists) {
    return false;
  }
  const b = before.data() || {};
  const a = after.data() || {};
  if ((a.gcalEventId || "") === (b.gcalEventId || "")) {
    return false;
  }
  for (const k of SYNC_FIELD_KEYS) {
    const vb = b[k];
    const va = a[k];
    if (!fieldValueEqual(vb, va)) {
      return false;
    }
  }
  return true;
}

/**
 * @param {*} a
 * @param {*} b
 * @return {boolean}
 */
function fieldValueEqual(a, b) {
  if (a === b) {
    return true;
  }
  if (!a && !b) {
    return true;
  }
  if (a && b && typeof a.isEqual === "function" && typeof b.isEqual === "function") {
    try {
      return a.isEqual(b);
    } catch {
      return false;
    }
  }
  return false;
}

/**
 * @param {string} careGroupId
 * @return {Promise<string>}
 */
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
 * @param {FirebaseFirestore.DocumentData|undefined} data
 * @return {string}
 */
function timezoneFromCareGroupDoc(data) {
  const d = data || {};
  const gc = d.groupCalendar;
  if (
    gc && typeof gc === "object"
    && gc.timezone != null && String(gc.timezone).trim()
  ) {
    return String(gc.timezone).trim();
  }
  if (d.groupTimezone != null && String(d.groupTimezone).trim()) {
    return String(d.groupTimezone).trim();
  }
  return "";
}

/**
 * Prefer `careGroups/{id}.groupCalendar.timezone` or `groupTimezone`, then
 * `config/groupSettings.timezone`, else UTC.
 * @param {string} careGroupId
 * @return {Promise<string>}
 */
async function loadGroupTimezone(careGroupId) {
  try {
    const cg = await db.doc("careGroups/" + careGroupId).get();
    if (cg.exists) {
      const tz = timezoneFromCareGroupDoc(cg.data());
      if (tz) {
        return tz;
      }
    }
  } catch (e) {
    console.error("loadGroupTimezone careGroupDoc failed", e);
  }

  try {
    const ref = db.doc("config/groupSettings");
    const snap = await ref.get();
    if (snap.exists) {
      const tz = snap.get("timezone");
      if (tz && String(tz).trim()) {
        return String(tz).trim();
      }
    }
  } catch (e) {
    console.error("loadGroupTimezone failed", e);
  }
  return "UTC";
}

/**
 * @param {string} uid
 * @return {Promise<string>}
 */
async function loadUserDisplayName(uid) {
  if (!uid) {
    return "";
  }
  try {
    const snap = await db.doc("users/" + uid).get();
    if (!snap.exists) {
      return "";
    }
    const d = snap.data() || {};
    const n =
      (d.displayName && String(d.displayName).trim()) ||
      (d.name && String(d.name).trim()) ||
      "";
    return n || "";
  } catch (e) {
    console.error("loadUserDisplayName failed", e);
    return "";
  }
}

/**
 * @param {string} careGroupId
 * @return {Promise<string>}
 */
async function loadCareGroupName(careGroupId) {
  try {
    const snap = await db.doc("careGroups/" + careGroupId).get();
    if (!snap.exists) {
      return "";
    }
    const d = snap.data() || {};
    const n =
      (d.name && String(d.name).trim()) ||
      (d.displayName && String(d.displayName).trim()) ||
      "";
    return n || "";
  } catch (e) {
    console.error("loadCareGroupName failed", e);
    return "";
  }
}

/**
 * @param {unknown} err
 * @return {boolean}
 */
function isNotFoundError(err) {
  const e =
    /** @type {{ code?: number, response?: { status?: number }, message?: string }} */ (err || {});
  if (e.response && e.response.status === 404) {
    return true;
  }
  if (e.code === 404) {
    return true;
  }
  const m = String(e.message || "");
  return /\b404\b/.test(m) || m.toLowerCase().includes("not found");
}

/**
 * @param {import("firebase-functions/v2/firestore").FirestoreEvent<import("firebase-functions/v2/firestore").Change<FirebaseFirestore.DocumentSnapshot>>} event
 */
async function syncHandler(event) {
  const {careGroupId, taskId} = event.params;
  const beforeSnap = event.data.before;
  const afterSnap = event.data.after;

  const keyJson = gcalServiceAccountKey.value();
  if (!keyJson || !String(keyJson).trim()) {
    console.warn("syncToGoogleCalendar: GCAL_SERVICE_ACCOUNT_KEY not configured");
    return;
  }

  const fallbackCal = (gcalCalendarId.value() || "").trim();

  /** @type {string} */
  let calendarIdResolved = "";
  try {
    const cgSnap = await db.doc("careGroups/" + careGroupId).get();
    if (cgSnap.exists) {
      calendarIdResolved = calendarIdFromCareGroupDoc(cgSnap.data());
    }
  } catch (e) {
    console.error("syncToGoogleCalendar: read care group failed", e);
  }
  if (!calendarIdResolved && fallbackCal) {
    calendarIdResolved = fallbackCal;
  }
  if (!calendarIdResolved) {
    console.warn(
      "syncToGoogleCalendar: no calendar id for care group " + careGroupId +
      ". Set careGroups/{id}.groupCalendar.calendarId (preferred) or GCAL_CALENDAR_ID."
    );
    return;
  }

  let calendar;
  try {
    const c = createCalendarClient({
      keyJson,
      calendarId: calendarIdResolved,
    });
    calendar = c.calendar;
  } catch (e) {
    console.error("syncToGoogleCalendar: create client failed", e);
    return;
  }

  /** @type {string|undefined} */
  let existingGcalId;
  if (beforeSnap && beforeSnap.exists) {
    const prev = beforeSnap.get("gcalEventId");
    if (prev) {
      existingGcalId = String(prev);
    }
  }

  if (onlySystemGcalWrite(beforeSnap, afterSnap)) {
    return;
  }

  if (!afterSnap || !afterSnap.exists) {
    if (existingGcalId) {
      try {
        await deleteEvent(calendar, calendarIdResolved, existingGcalId);
      } catch (e) {
        if (!isNotFoundError(e)) {
          console.error("syncToGoogleCalendar: delete on task remove failed", e);
        }
      }
    }
    return;
  }

  const d = afterSnap.data() || {};
  const status = d.status != null ? String(d.status) : "open";
  const gcalEventId = d.gcalEventId != null ? String(d.gcalEventId) : "";

  if (status === "draft") {
    if (gcalEventId) {
      try {
        await deleteEvent(calendar, calendarIdResolved, gcalEventId);
      } catch (e) {
        if (!isNotFoundError(e)) {
          console.error("syncToGoogleCalendar: delete draft failed", e);
        }
      }
      try {
        await afterSnap.ref.update({
          gcalEventId: FieldValue.delete(),
        });
      } catch (e2) {
        console.error("syncToGoogleCalendar: clear gcalEventId after draft failed", e2);
      }
    }
    return;
  }

  if (status === "cancelled") {
    if (gcalEventId) {
      try {
        await deleteEvent(calendar, calendarIdResolved, gcalEventId);
      } catch (e) {
        if (!isNotFoundError(e)) {
          console.error("syncToGoogleCalendar: delete cancelled failed", e);
        }
      }
      try {
        await afterSnap.ref.update({
          gcalEventId: FieldValue.delete(),
        });
      } catch (e2) {
        console.error("syncToGoogleCalendar: clear gcalEventId after cancel failed", e2);
      }
    }
    return;
  }

  const dueCalendarDate = d.dueCalendarDate != null ? String(d.dueCalendarDate).trim() : "";
  const dueTime = d.dueTime != null ? String(d.dueTime).trim() : "";
  const hasDueParts = !!(dueCalendarDate && dueTime && /^\d{4}-\d{2}-\d{2}$/.test(dueCalendarDate) &&
    /^\d{1,2}:\d{2}$/.test(dueTime));
  const dueAt = d.dueAt;

  if (!hasDueParts && !(dueAt && typeof dueAt.toMillis === "function")) {
    if (gcalEventId) {
      try {
        await deleteEvent(calendar, calendarIdResolved, gcalEventId);
      } catch (e) {
        if (!isNotFoundError(e)) {
          console.error("syncToGoogleCalendar: delete unscheduled failed", e);
        }
      }
      try {
        await afterSnap.ref.update({
          gcalEventId: FieldValue.delete(),
        });
      } catch (e2) {
        console.error("syncToGoogleCalendar: clear gcalEventId after unscheduled failed", e2);
      }
    }
    return;
  }

  let timezone = "UTC";
  try {
    timezone = await loadGroupTimezone(careGroupId);
  } catch (_) {
    timezone = "UTC";
  }

  const assignUid = d.assignedTo != null ? String(d.assignedTo) : "";
  const assigneeName = assignUid ? await loadUserDisplayName(assignUid) : "";

  let recipientSuffix = d.careRecipientName != null ? String(d.careRecipientName).trim() : "";
  if (!recipientSuffix) {
    recipientSuffix = await loadCareGroupName(careGroupId);
  }

  const title = d.title != null ? String(d.title) : "Task";

  /** @type {import("googleapis").calendar_v3.Schema$Event|null} */
  let body;
  try {
    body = buildEvent({
      title,
      notes: d.notes != null ? String(d.notes) : "",
      description: d.description != null ? String(d.description) : "",
      dueCalendarDate: hasDueParts ? dueCalendarDate : "",
      dueTime: hasDueParts ? dueTime : "",
      dueAt: dueAt || undefined,
      timezone,
      durationMinutes: d.durationMinutes != null ? Number(d.durationMinutes) : 60,
      assigneeName,
      careRecipientSuffix: recipientSuffix || undefined,
    });
  } catch (e) {
    console.error("syncToGoogleCalendar: buildEvent failed", e);
    return;
  }

  if (!body) {
    return;
  }

  try {
    if (gcalEventId) {
      try {
        await updateEvent(calendar, calendarIdResolved, gcalEventId, body);
      } catch (e) {
        if (isNotFoundError(e)) {
          const newId = await insertEvent(calendar, calendarIdResolved, body);
          await afterSnap.ref.update({gcalEventId: newId});
        } else {
          console.error("syncToGoogleCalendar: update failed", e);
        }
      }
    } else {
      const newId = await insertEvent(calendar, calendarIdResolved, body);
      await afterSnap.ref.update({gcalEventId: newId});
    }
  } catch (e) {
    console.error("syncToGoogleCalendar: insert/sync failed", e);
  }
}

exports.syncToGoogleCalendar = onDocumentWritten(
  {
    document: "careGroups/{careGroupId}/tasks/{taskId}",
    region: "us-central1",
    secrets: [gcalServiceAccountKey, gcalCalendarId],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  syncHandler
);
