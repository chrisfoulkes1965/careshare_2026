"use strict";

const {DateTime} = require("luxon");

/**
 * @param {string} ymd
 * @return {{ year: number, month: number, day: number }}
 */
function fromYmd(ymd) {
  const parts = ymd.split("-");
  return {
    year: parseInt(parts[0], 10),
    month: parseInt(parts[1], 10),
    day: parseInt(parts[2], 10),
  };
}

/**
 * @param {object} input
 * @param {string} input.title
 * @param {string} [input.notes]
 * @param {string} [input.description]
 * @param {string} [input.dueCalendarDate] yyyy-MM-dd
 * @param {string} [input.dueTime] HH:mm
 * @param {import("firebase-admin/firestore").Timestamp|undefined} input.dueAt
 * @param {string} input.timezone IANA, e.g. Europe/London
 * @param {number|undefined} input.durationMinutes
 * @param {string} [input.assigneeName]
 * @param {string} [input.careRecipientSuffix] appended as " — suffix" to summary when set
 * @return {import("googleapis").calendar_v3.Schema$Event|null}
 */
function buildEvent(input) {
  const duration = Math.max(
    15,
    Number.isFinite(Number(input.durationMinutes)) ? Number(input.durationMinutes) : 60
  );
  const timezone = (input.timezone || "UTC").trim() || "UTC";

  /** @type {DateTime|null} */
  let start = null;
  /** @type {string} */
  let tzForEvent = timezone;

  const dcd = input.dueCalendarDate && String(input.dueCalendarDate).trim();
  const dtStr = input.dueTime && String(input.dueTime).trim();
  if (dcd && /^\d{4}-\d{2}-\d{2}$/.test(dcd) && dtStr && /^\d{1,2}:\d{2}$/.test(dtStr)) {
    const hm = dtStr.match(/^(\d{1,2}):(\d{2})$/);
    if (hm) {
      const h = parseInt(hm[1], 10);
      const mi = parseInt(hm[2], 10);
      const ymd = fromYmd(dcd);
      start = DateTime.fromObject(
        {
          year: ymd.year,
          month: ymd.month,
          day: ymd.day,
          hour: h,
          minute: mi,
          second: 0,
          millisecond: 0,
        },
        {zone: tzForEvent}
      );
    }
  }

  if (!start || !start.isValid) {
    const dueAt = input.dueAt;
    if (!dueAt || typeof dueAt.toMillis !== "function") {
      return null;
    }
    tzForEvent = "UTC";
    start = DateTime.fromMillis(dueAt.toMillis(), {zone: "utc"});
  }

  if (!start.isValid) {
    return null;
  }

  const end = start.plus({minutes: duration});
  const notes = (input.notes || input.description || "").trim();
  const assignLine =
    input.assigneeName && input.assigneeName.trim()
      ? "\n\nAssigned to: " + input.assigneeName.trim()
      : "";
  const fullDesc = (notes + assignLine).trim();

  const summaryBase = (input.title || "Task").trim() || "Task";
  const suffix = input.careRecipientSuffix && input.careRecipientSuffix.trim();
  const summary = suffix ? summaryBase + " — " + suffix : summaryBase;

  return {
    summary,
    description: fullDesc || undefined,
    start: {dateTime: start.toISO(), timeZone: tzForEvent},
    end: {dateTime: end.toISO(), timeZone: tzForEvent},
  };
}

module.exports = {buildEvent};
