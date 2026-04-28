const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineString} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// Invitation emails via Resend (https://resend.com). Params: RESEND_*, CARESHARE_APP_URL.
// See: https://firebase.google.com/docs/functions/config-env
const careshareAppUrl = defineString("CARESHARE_APP_URL", {
  default: "https://careshare-2026.web.app",
  description: "Public web app base URL, no trailing slash.",
});
const resendApiKey = defineString("RESEND_API_KEY", {
  default: "",
  description: "Resend API key (re_...). Empty = skip email (invitation is still created).",
});
const resendFromEmail = defineString("RESEND_FROM_EMAIL", {
  default: "",
  description: "From address (verified in Resend or onboarding@resend.dev for tests).",
});
const resendFromName = defineString("RESEND_FROM_NAME", {
  default: "CareShare",
  description: "From display name for Resend.",
});

/**
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {Object} d
 * @param {string} invitationId
 * @return {Promise<void>}
 */
async function deliverInvitationEmail(docRef, d, invitationId) {
  const invited = d.invitedEmail
    ? String(d.invitedEmail).toLowerCase().trim()
    : "";
  if (!invited) {
    return;
  }
  const careGroupId = d.careGroupId != null ? String(d.careGroupId) : "";
  const dataCareGroupId =
    d.dataCareGroupId != null ? String(d.dataCareGroupId).trim() : "";
  const invitedBy = d.invitedBy != null ? String(d.invitedBy) : "";
  const status = d.status != null ? String(d.status) : "";
  if (status !== "pending") {
    return;
  }

  const apiKey = (resendApiKey.value() || "").trim();
  const from = (resendFromEmail.value() || "").trim();
  const fromName = (resendFromName.value() || "CareShare").trim() || "CareShare";

  if (!apiKey || !from) {
    await docRef.update({
      emailDelivery: "skipped_config",
      emailNotAttemptedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  const noDoc = {exists: false, get: () => null};
  let userSnap = noDoc;
  let teamSnap = noDoc;
  let dataSnap = noDoc;
  try {
    [userSnap, teamSnap, dataSnap] = await Promise.all([
      invitedBy ? db.doc("users/" + invitedBy).get() : Promise.resolve(noDoc),
      careGroupId
        ? db.doc("careGroups/" + careGroupId).get()
        : Promise.resolve(noDoc),
      dataCareGroupId
        ? db.doc("careGroups/" + dataCareGroupId).get()
        : Promise.resolve(noDoc),
    ]);
  } catch (e) {
    console.error("deliverInvitationEmail: read context failed", e);
  }

  let inviterName = "A CareShare member";
  if (userSnap && userSnap.exists) {
    const u = userSnap.data() || {};
    const n = (u.displayName && String(u.displayName).trim()) ||
      (u.name && String(u.name).trim()) || "";
    if (n) {
      inviterName = n;
    }
  }
  const nameFrom = (snap) => {
    if (!snap || !snap.exists) {
      return "";
    }
    const gd = snap.data() || {};
    return (gd.name && String(gd.name).trim()) ||
      (gd.displayName && String(gd.displayName).trim()) || "";
  };
  let groupName = "your care team";
  const nTeam = nameFrom(teamSnap);
  const nData = nameFrom(dataSnap);
  if (nTeam) {
    groupName = nTeam;
  } else if (nData) {
    groupName = nData;
  }

  const base = String(careshareAppUrl.value() || "https://careshare-2026.web.app")
    .replace(/\/$/, "");
  const signInUrl = new URL("/sign-in", base + "/");
  signInUrl.searchParams.set("email", invited);
  if (invitationId) {
    signInUrl.searchParams.set("invite", invitationId);
  }
  const openLink = signInUrl.toString();

  const subj = "You're invited to " + groupName + " on CareShare";
  const textBody =
    inviterName + " invited you to join the care team \"" + groupName + "\" in CareShare.\n\n" +
    "Open this link to sign in or create an account. Use the same email this message was sent to: " +
    invited + "\n\n" +
    openLink + "\n\n" +
    "If you were not expecting this, you can ignore this email.\n\n" +
    "— " + fromName;
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const htmlBody =
    "<p>" + esc(inviterName) + " invited you to join the care team <strong>" + esc(groupName) +
    "</strong> in CareShare.</p>" +
    "<p>Sign in or register using the <strong>same email</strong> this invitation was sent to: " +
    esc(invited) + "</p>" +
    "<p><a href=\"" + esc(openLink) + "\">Open CareShare</a></p>" +
    "<p style=\"color:#666;font-size:12px;\">If you were not expecting this, you can ignore this email.</p>";

  const fromResend = fromName
    ? String(fromName).replace(/[\r\n<>]/g, " ").trim() + " <" + from + ">"
    : from;

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromResend,
        to: [invited],
        subject: subj,
        text: textBody,
        html: htmlBody,
      }),
    });
    if (res.status < 200 || res.status >= 300) {
      const t = await res.text();
      throw new Error("Resend HTTP " + res.status + ": " + t);
    }
    await docRef.update({
      emailSentAt: FieldValue.serverTimestamp(),
      emailDelivery: "sent",
      emailDeliveryError: FieldValue.delete(),
    });
  } catch (e) {
    const msg = String((e && e.message) || e).slice(0, 2000);
    console.error("deliverInvitationEmail: failed", msg);
    await docRef.update({
      emailDelivery: "error",
      emailDeliveryError: msg,
      emailFailedAt: FieldValue.serverTimestamp(),
    });
  }
}

/**
 * @param {import("firebase-admin/firestore").Timestamp|undefined} a
 * @param {import("firebase-admin/firestore").Timestamp|undefined} b
 * @return {boolean}
 */
function tsEqual(a, b) {
  if (!a || !b) {
    return false;
  }
  if (a instanceof Timestamp && b instanceof Timestamp) {
    return a.isEqual(b);
  }
  return a.toMillis() === b.toMillis();
}

/**
 * When a new in-app chat message is written, send FCM to other channel members.
 */
exports.onChatMessageCreated = onDocumentCreated(
  {
    document: "careGroups/{careGroupId}/chatChannels/{channelId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }
    const d = snap.data();
    if (!d) {
      return;
    }
    const text = d.text != null ? String(d.text) : "";
    const createdBy = d.createdBy != null ? String(d.createdBy) : "";
    if (!createdBy) {
      return;
    }
    const {careGroupId, channelId} = event.params;

    const chRef = db.doc(
      "careGroups/" + careGroupId + "/chatChannels/" + channelId
    );
    const ch = await chRef.get();
    if (!ch.exists) {
      return;
    }
    const m = ch.data() || {};
    const memberUids = Array.isArray(m.memberUids) ? m.memberUids.map(String) : [];
    const channelName = m.name && String(m.name).trim() ? String(m.name).trim() : "Chat";
    if (memberUids.length === 0) {
      return;
    }

    const sSnap = await db.doc("users/" + createdBy).get();
    const senderName = sSnap.exists
      ? String(sSnap.get("displayName") || "Someone").trim() || "Someone"
      : "Someone";
    const preview = text.length > 120 ? text.slice(0, 120) + "\u2026" : (text || "(message)");

    const messages = [];
    for (const uid of memberUids) {
      if (uid === createdBy) {
        continue;
      }
      const tokCol = await db.collection("users/" + uid + "/devicePushTokens").get();
      for (const doc of tokCol.docs) {
        const token = (doc.get("token") && String(doc.get("token"))) || "";
        if (!token) {
          continue;
        }
        messages.push({
          token: token,
          notification: {
            title: "CareShare \u00B7 " + channelName,
            body: senderName + ": " + preview,
          },
          data: {
            type: "chat",
            careGroupId: String(careGroupId),
            channelId: String(channelId),
          },
          android: {
            notification: {
              channelId: "careshare_chat",
            },
          },
        });
      }
    }
    if (messages.length === 0) {
      return;
    }
    const res = await messaging.sendEach(messages);
    console.log(
      "onChatMessageCreated: sent=" + messages.length +
      " success=" + res.successCount +
      " fail=" + res.failureCount
    );
  }
);

/**
 * When a care-group invitation is created, email the invitee a sign-in link.
 */
exports.onCareInvitationCreated = onDocumentCreated(
  {
    document: "invitations/{invitationId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }
    const d = snap.data() || {};
    if (!d.invitedEmail) {
      return;
    }
    if (String(d.status || "") !== "pending") {
      return;
    }
    const invitationId = String(event.params.invitationId || "");
    try {
      await deliverInvitationEmail(snap.ref, d, invitationId);
    } catch (e) {
      const msg = String((e && e.message) || e).slice(0, 2000);
      console.error("onCareInvitationCreated: unhandled", msg);
      try {
        await snap.ref.update({
          emailDelivery: "error",
          emailDeliveryError: "Function error: " + msg,
          emailFailedAt: FieldValue.serverTimestamp(),
        });
      } catch (e2) {
        console.error("onCareInvitationCreated: could not write error to doc", e2);
      }
    }
  }
);

/**
 * When a principal sets [resendEmailRequestedAt] (e.g. user tapped “Resend email” in the app),
 * send the same invitation message again. Ignores other updates to the same field value.
 */
exports.onCareInvitationResendEmail = onDocumentUpdated(
  {
    document: "invitations/{invitationId}",
    region: "us-central1",
  },
  async (event) => {
    const be = event.data.before;
    const af = event.data.after;
    if (!af.exists) {
      return;
    }
    const a = af.data() || {};
    if (String(a.status || "") !== "pending") {
      return;
    }
    const b = be.exists ? (be.data() || {}) : {};
    const ar = a.resendEmailRequestedAt;
    const br = b.resendEmailRequestedAt;
    if (!ar) {
      return;
    }
    if (tsEqual(ar, br)) {
      return;
    }
    const invitationId = String(event.params.invitationId || "");
    try {
      await deliverInvitationEmail(af.ref, a, invitationId);
    } catch (e) {
      const msg = String((e && e.message) || e).slice(0, 2000);
      console.error("onCareInvitationResendEmail: unhandled", msg);
      try {
        await af.ref.update({
          emailDelivery: "error",
          emailDeliveryError: "Function error: " + msg,
          emailFailedAt: FieldValue.serverTimestamp(),
        });
      } catch (e2) {
        console.error("onCareInvitationResendEmail: could not write error to doc", e2);
      }
    }
  }
);

const {syncToGoogleCalendar} = require("./gcal/syncToGoogleCalendar");
exports.syncToGoogleCalendar = syncToGoogleCalendar;
