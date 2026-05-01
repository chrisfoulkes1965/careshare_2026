const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, FieldPath, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {DateTime} = require("luxon");
const crypto = require("crypto");
const {doseSlotKeyFromLuxon, medicationAckDocId} = require("./medicationAckShared");

const db = getFirestore();
const messaging = getMessaging();

/**
 * Luxon weekday: ISO 1=Mon … 7=Sun → plugin day 1=Sun … 7=Sat (matches Flutter).
 * @param {number} luxonWeekday
 * @return {number}
 */
function luxonWeekdayToPluginDay(luxonWeekday) {
  return luxonWeekday === 7 ? 1 : luxonWeekday + 1;
}

/**
 * @param {number} minuteOfDay
 * @param {number} startMin
 * @param {number} endMin
 * @return {boolean}
 */
function minuteInQuietWindow(minuteOfDay, startMin, endMin) {
  if (startMin === endMin) {
    return false;
  }
  if (startMin < endMin) {
    return minuteOfDay >= startMin && minuteOfDay < endMin;
  }
  return minuteOfDay >= startMin || minuteOfDay < endMin;
}

/**
 * @param {import("luxon").DateTime} when
 * @param {number|null} startMin
 * @param {number|null} endMin
 * @return {import("luxon").DateTime}
 */
function adjustAwayFromQuietHours(when, startMin, endMin) {
  if (startMin == null || endMin == null || startMin === endMin) {
    return when;
  }
  let cur = when;
  for (let i = 0; i < 2880; i++) {
    const m = cur.hour * 60 + cur.minute;
    if (!minuteInQuietWindow(m, startMin, endMin)) {
      return cur;
    }
    cur = cur.plus({minutes: 1});
  }
  return when;
}

/**
 * @param {FirebaseFirestore.DocumentData} med
 * @param {import("luxon").DateTime} localDate
 * @return {boolean}
 */
function occursOnDay(med, localDate) {
  const st = med.reminderSchedule != null ? String(med.reminderSchedule) : "daily";
  if (st === "daily") {
    return true;
  }
  if (st === "weekly") {
    const wd = luxonWeekdayToPluginDay(localDate.weekday);
    const days = Array.isArray(med.reminderWeekdays) ? med.reminderWeekdays : [];
    return days.some((d) => Number(d) === wd);
  }
  if (st === "monthly") {
    const dom = localDate.day;
    const md = Array.isArray(med.reminderMonthDays) ? med.reminderMonthDays : [];
    return md.some((d) => Number(d) === dom);
  }
  return false;
}

/**
 * @param {FirebaseFirestore.DocumentData} med
 * @return {{hour: number, minute: number}[]}
 */
function parseReminderTimes(med) {
  const raw = med.reminderTimes;
  if (!Array.isArray(raw)) {
    return [];
  }
  const out = [];
  for (const e of raw) {
    if (!e || typeof e !== "object") {
      continue;
    }
    const h = Number(e.h);
    const mm = Number(e.m);
    if (!Number.isFinite(h) || !Number.isFinite(mm)) {
      continue;
    }
    out.push({
      hour: Math.max(0, Math.min(23, Math.floor(h))),
      minute: Math.max(0, Math.min(59, Math.floor(mm))),
    });
  }
  return out;
}

/**
 * @param {FirebaseFirestore.DocumentData} med
 * @return {boolean}
 */
function validReminderSchedule(med) {
  if (med.reminderEnabled !== true) {
    return false;
  }
  const times = parseReminderTimes(med);
  if (times.length === 0) {
    return false;
  }
  const st = med.reminderSchedule != null ? String(med.reminderSchedule) : "daily";
  if (st === "weekly") {
    const d = med.reminderWeekdays;
    if (!Array.isArray(d) || d.length === 0) {
      return false;
    }
  }
  if (st === "monthly") {
    const d = med.reminderMonthDays;
    if (!Array.isArray(d) || d.length === 0) {
      return false;
    }
  }
  return true;
}

/**
 * @param {string} careGroupDocId
 * @return {Promise<string>}
 */
async function resolveDataCareGroupId(careGroupDocId) {
  const snap = await db.doc("careGroups/" + careGroupDocId).get();
  if (!snap.exists) {
    return careGroupDocId;
  }
  const linked = snap.get("careGroupId");
  const t = linked != null ? String(linked).trim() : "";
  return t.length > 0 ? t : careGroupDocId;
}

/**
 * @param {string} uid
 * @param {string} dataCareGroupId
 * @param {string} dateStr yyyy-LL-dd
 * @param {number} hour
 * @param {number} minute
 * @param {string[]} medIds
 * @return {string}
 */
function dedupDocId(dataCareGroupId, dateStr, hour, minute, medIds) {
  const raw =
    dataCareGroupId + "|" + dateStr + "|" + hour + "|" + minute + "|" + medIds.sort().join(",");
  return crypto.createHash("sha256").update(raw).digest("hex").slice(0, 48);
}

/**
 * Every 10 minutes: mirror due-dose reminders via FCM for users who saved a timezone.
 * Requires client-written `users/{uid}.medicationRemindersTimezone` (IANA).
 */
exports.scheduledMedicationReminders = onSchedule(
  {
    schedule: "every 10 minutes",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const uidToTokens = new Map();
    let lastDoc = null;
    const batchSize = 400;
    for (;;) {
      let q = db.collectionGroup("devicePushTokens").orderBy(FieldPath.documentId()).limit(batchSize);
      if (lastDoc != null) {
        q = q.startAfter(lastDoc);
      }
      const snap = await q.get();
      if (snap.empty) {
        break;
      }
      for (const d of snap.docs) {
        const parent = d.ref.parent.parent;
        if (!parent) {
          continue;
        }
        const uid = parent.id;
        const token = d.get("token");
        const t = token != null ? String(token).trim() : "";
        if (!t) {
          continue;
        }
        if (!uidToTokens.has(uid)) {
          uidToTokens.set(uid, new Set());
        }
        uidToTokens.get(uid).add(t);
      }
      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < batchSize) {
        break;
      }
    }

    let sentBatches = 0;
    for (const [uid, tokenSet] of uidToTokens) {
      const tokens = [...tokenSet];
      if (tokens.length === 0) {
        continue;
      }
      let userSnap;
      try {
        userSnap = await db.doc("users/" + uid).get();
      } catch (e) {
        console.warn("medReminder user read", uid, String(e && e.message ? e.message : e));
        continue;
      }
      if (!userSnap.exists) {
        continue;
      }
      const tzName = userSnap.get("medicationRemindersTimezone");
      if (!tzName || typeof tzName !== "string" || tzName.trim().length === 0) {
        continue;
      }
      const ap = userSnap.get("alertPreferences") || {};
      const medDue = ap.medicationDue || {};
      if (medDue.pushApp === false) {
        continue;
      }
      const activeCg = userSnap.get("activeCareGroupId");
      if (!activeCg || typeof activeCg !== "string") {
        continue;
      }
      const cgStr = String(activeCg).trim();
      if (!cgStr) {
        continue;
      }
      let memSnap;
      try {
        memSnap = await db.doc("careGroups/" + cgStr + "/members/" + uid).get();
      } catch (_) {
        continue;
      }
      if (!memSnap.exists) {
        continue;
      }

      let dataId;
      try {
        dataId = await resolveDataCareGroupId(cgStr);
      } catch (_) {
        continue;
      }

      let cgDataSnap;
      try {
        cgDataSnap = await db.doc("careGroups/" + dataId).get();
      } catch (_) {
        continue;
      }
      const cgData = cgDataSnap.exists ? (cgDataSnap.data() || {}) : {};
      let qStart = cgData.medicationQuietHoursStartMinute;
      let qEnd = cgData.medicationQuietHoursEndMinute;
      if (qStart == null) {
        qStart = cgData.quietHoursStartMinute;
      }
      if (qEnd == null) {
        qEnd = cgData.quietHoursEndMinute;
      }
      const qs = typeof qStart === "number" ? qStart : (qStart != null ? Number(qStart) : null);
      const qe = typeof qEnd === "number" ? qEnd : (qEnd != null ? Number(qEnd) : null);
      const quietOk =
        qs != null &&
        qe != null &&
        Number.isFinite(qs) &&
        Number.isFinite(qe) &&
        qs !== qe;

      let medSnap;
      try {
        medSnap = await db.collection("careGroups/" + dataId + "/medications").get();
      } catch (_) {
        continue;
      }

      let localNow;
      try {
        localNow = DateTime.now().setZone(String(tzName).trim());
      } catch (_) {
        continue;
      }
      if (!localNow.isValid) {
        continue;
      }

      /** @type {Map<string, {ids: Set<string>, names: string[], adjusted: import('luxon').DateTime}>} */
      const slotGroups = new Map();

      for (const doc of medSnap.docs) {
        const med = doc.data() || {};
        if (!validReminderSchedule(med)) {
          continue;
        }
        if (!occursOnDay(med, localNow)) {
          continue;
        }
        const times = parseReminderTimes(med);
        const name = med.name != null ? String(med.name).trim() : "";
        for (const tm of times) {
          const nominal = localNow.startOf("day").set({
            hour: tm.hour,
            minute: tm.minute,
            second: 0,
            millisecond: 0,
          });
          if (!nominal.isValid) {
            continue;
          }
          const adjusted = quietOk
            ? adjustAwayFromQuietHours(nominal, qs, qe)
            : nominal;
          const diffMs = localNow.toMillis() - adjusted.toMillis();
          if (diffMs < -120000 || diffMs > 14 * 60 * 1000) {
            continue;
          }
          const key =
            adjusted.toFormat("yyyy-LL-dd") +
            "|" +
            adjusted.hour +
            "|" +
            adjusted.minute;
          if (!slotGroups.has(key)) {
            slotGroups.set(key, {ids: new Set(), names: [], adjusted});
          }
          const g = slotGroups.get(key);
          g.ids.add(doc.id);
          if (name) {
            g.names.push(name);
          }
        }
      }

      for (const [mapKey, group] of slotGroups) {
        const ids = [...group.ids].sort();
        if (ids.length === 0) {
          continue;
        }
        const parts = mapKey.split("|");
        const dateStr = parts[0] || localNow.toFormat("yyyy-LL-dd");
        const hour = Number(parts[1]);
        const minute = Number(parts[2]);
        const dedupId = dedupDocId(
          dataId,
          dateStr,
          hour,
          minute,
          ids,
        );
        const dedupRef = db.doc("users/" + uid + "/medicationReminderDedup/" + dedupId);
        try {
          const prev = await dedupRef.get();
          if (prev.exists) {
            continue;
          }
        } catch (_) {
          continue;
        }

        const uniqNames = [...new Set(group.names)].sort();
        const body =
          uniqNames.length === 1
            ? "Time to take: " + uniqNames[0]
            : "Time to take: " + uniqNames.slice(0, 3).join(", ") +
              (uniqNames.length > 3 ? "\u2026" : "");

        const doseSk = doseSlotKeyFromLuxon(group.adjusted);

        const messages = tokens.map((tok) => ({
          token: tok,
          notification: {
            title: "Medication",
            body: body.length > 180 ? body.slice(0, 177) + "\u2026" : body,
          },
          data: {
            type: "medication",
            careGroupId: String(dataId),
            medicationIds: ids.join(","),
            slotKey: doseSk,
          },
          android: {
            notification: {
              channelId: "careshare_medications",
            },
          },
        }));

        try {
          const res = await messaging.sendEach(messages);
          sentBatches += res.successCount;
          await dedupRef.set({
            sentAt: FieldValue.serverTimestamp(),
            careGroupId: String(dataId),
            medicationIds: ids,
          });
          const ackId = medicationAckDocId(String(dataId), doseSk, ids);
          const ackRef = db.doc(
            "careGroups/" + dataId + "/medicationReminderAcks/" + ackId
          );
          const ackSnap = await ackRef.get();
          if (!ackSnap.exists) {
            await ackRef.set({
              slotKey: doseSk,
              medicationIds: ids,
              dueAt: Timestamp.fromMillis(group.adjusted.toMillis()),
              needsConfirmation: true,
              principalAlertSent: false,
              updatedAt: FieldValue.serverTimestamp(),
            });
          } else if (ackSnap.get("needsConfirmation") === true) {
            await ackRef.update({
              slotKey: doseSk,
              medicationIds: ids,
              dueAt: Timestamp.fromMillis(group.adjusted.toMillis()),
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          console.warn("medReminder send failed", uid, String(e && e.message ? e.message : e));
        }
      }
    }

    console.log("scheduledMedicationReminders: uidCount=" + uidToTokens.size + " approxSent=" + sentBatches);
  },
);
