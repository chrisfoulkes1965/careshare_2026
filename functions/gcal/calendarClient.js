"use strict";

const {google} = require("googleapis");

/**
 * @param {{ keyJson: string }} opts
 * @return {{ calendar: import("googleapis").calendar_v3.Calendar, calendarId: string }}
 */
function createCalendarClient(opts) {
  const parsed = JSON.parse(opts.keyJson);
  const auth = new google.auth.GoogleAuth({
    credentials: parsed,
    scopes: ["https://www.googleapis.com/auth/calendar.events"],
  });
  return {
    calendar: google.calendar({version: "v3", auth}),
    calendarId: opts.calendarId.trim(),
  };
}

/**
 * @param {import("googleapis").calendar_v3.Calendar} calendar
 * @param {string} calendarId
 * @param {string} eventId
 */
async function deleteEvent(calendar, calendarId, eventId) {
  await calendar.events.delete({
    calendarId,
    eventId,
    sendUpdates: "none",
  });
}

/**
 * @param {import("googleapis").calendar_v3.Calendar} calendar
 * @param {string} calendarId
 * @param {import("googleapis").calendar_v3.Schema$Event} body
 * @return {Promise<string>} new event id
 */
async function insertEvent(calendar, calendarId, body) {
  const res = await calendar.events.insert({
    calendarId,
    requestBody: body,
    sendUpdates: "none",
  });
  const id = res.data.id;
  if (!id) {
    throw new Error("insertEvent: missing id in response");
  }
  return id;
}

/**
 * @param {import("googleapis").calendar_v3.Calendar} calendar
 * @param {string} calendarId
 * @param {string} eventId
 * @param {import("googleapis").calendar_v3.Schema$Event} body
 */
async function updateEvent(calendar, calendarId, eventId, body) {
  await calendar.events.update({
    calendarId,
    eventId,
    requestBody: body,
    sendUpdates: "none",
  });
}

/**
 * @param {import("googleapis").calendar_v3.Calendar} calendar
 * @param {string} calendarId
 * @param {string} timeMin RFC3339
 * @param {string} timeMax RFC3339
 * @return {Promise<import("googleapis").calendar_v3.Schema$Event[]>}
 */
async function listEventsBetween(calendar, calendarId, timeMin, timeMax) {
  /** @type {import("googleapis").calendar_v3.Params$Resource$Events$List>} */
  const req = {
    calendarId,
    timeMin,
    timeMax,
    singleEvents: true,
    orderBy: "startTime",
    maxResults: 2500,
    showDeleted: false,
  };
  const res = await calendar.events.list(req);
  return res.data.items || [];
}

module.exports = {
  createCalendarClient,
  deleteEvent,
  insertEvent,
  updateEvent,
  listEventsBetween,
};
