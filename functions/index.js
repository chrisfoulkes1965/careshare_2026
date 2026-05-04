const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineString} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

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

  // Public landing copy for /sign-in?invite=… (readable when status is pending; see Firestore rules).
  try {
    await docRef.update({
      inviteLandingCareGroupName: groupName,
      inviteLandingInviterName: inviterName,
    });
  } catch (e) {
    console.error("deliverInvitationEmail: inviteLanding fields failed", e);
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

/**
 * @param {{to: string, subject: string, textBody: string, htmlBody: string}} opts
 * @return {Promise<void>}
 */
async function sendTransactionalResendEmail(opts) {
  const to = (opts.to || "").trim().toLowerCase();
  const apiKey = (resendApiKey.value() || "").trim();
  const from = (resendFromEmail.value() || "").trim();
  const fromName = (resendFromName.value() || "CareShare").trim() || "CareShare";
  if (!to || !apiKey || !from) {
    console.warn("sendTransactionalResendEmail: skipped (missing to, API key, or from)");
    return;
  }
  const fromResend = fromName
    ? String(fromName).replace(/[\r\n<>]/g, " ").trim() + " <" + from + ">"
    : from;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromResend,
      to: [to],
      subject: opts.subject,
      text: opts.textBody,
      html: opts.htmlBody,
    }),
  });
  if (res.status < 200 || res.status >= 300) {
    const t = await res.text();
    throw new Error("Resend HTTP " + res.status + ": " + t);
  }
}

/**
 * When an expense moves to **rejected**, email the submitter with the reason.
 */
exports.onCareGroupExpenseRejectedEmail = onDocumentUpdated(
  {
    document: "careGroups/{careGroupId}/expenses/{expenseId}",
    region: "us-central1",
  },
  async (event) => {
    const be = event.data.before;
    const af = event.data.after;
    if (!af.exists) {
      return;
    }
    const b = be.exists ? (be.data() || {}) : {};
    const a = af.data() || {};
    const beforeS = b.expenseStatus != null ? String(b.expenseStatus) : "approved";
    const afterS = a.expenseStatus != null ? String(a.expenseStatus) : "approved";
    if (beforeS === "rejected" || afterS !== "rejected") {
      return;
    }
    const payeeUid = a.createdBy != null ? String(a.createdBy) : "";
    if (!payeeUid) {
      return;
    }
    let email = "";
    try {
      const u = await db.doc("users/" + payeeUid).get();
      if (u.exists) {
        const em = u.get("email");
        if (em != null) {
          email = String(em).trim().toLowerCase();
        }
      }
    } catch (e) {
      console.error("onCareGroupExpenseRejectedEmail: user read failed", e);
    }
    if (!email) {
      console.warn("onCareGroupExpenseRejectedEmail: no email for uid", payeeUid);
      return;
    }
    const title = a.title != null ? String(a.title) : "Expense";
    const cur = a.currency != null ? String(a.currency) : "GBP";
    const amt = a.amount != null ? Number(a.amount) : 0;
    const reason = a.rejectionReason != null ? String(a.rejectionReason) : "";
    const {careGroupId} = event.params;
    let groupName = "your care team";
    try {
      const g = await db.doc("careGroups/" + careGroupId).get();
      if (g.exists) {
        const gd = g.data() || {};
        const n = (gd.name && String(gd.name).trim()) ||
          (gd.displayName && String(gd.displayName).trim()) || "";
        if (n) {
          groupName = n;
        }
      }
    } catch (_) {
      // ignore
    }
    const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const subj = "CareShare · Expense not approved · " + groupName;
    const textBody =
      "An expense you submitted was not approved for \"" + groupName + "\" in CareShare.\n\n" +
      "Expense: " + title + "\n" +
      "Amount: " + cur + " " + String(amt) + "\n\n" +
      "Reason:\n" + reason + "\n\n" +
      "Open the CareShare app to review or submit an updated claim if appropriate.\n\n" +
      "— CareShare";
    const htmlBody =
      "<p>An expense you submitted was <strong>not approved</strong> for <strong>" + esc(groupName) +
      "</strong> in CareShare.</p>" +
      "<p><strong>" + esc(title) + "</strong> · " + esc(cur) + " " + esc(String(amt)) + "</p>" +
      "<p><strong>Reason</strong></p><p style=\"white-space:pre-wrap;\">" + esc(reason) + "</p>" +
      "<p style=\"color:#666;font-size:12px;\">Open the CareShare app for details.</p>";
    try {
      await sendTransactionalResendEmail({
        to: email,
        subject: subj,
        textBody: textBody,
        htmlBody: htmlBody,
      });
    } catch (e) {
      console.error("onCareGroupExpenseRejectedEmail: send failed", String((e && e.message) || e));
    }
  }
);

/**
 * One email per payment batch ([expensePaymentClaims]) listing total and titles preview.
 */
exports.onExpensePaymentClaimCreatedEmail = onDocumentCreated(
  {
    document: "careGroups/{careGroupId}/expensePaymentClaims/{claimId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }
    const d = snap.data() || {};
    const payeeUid = d.payeeUid != null ? String(d.payeeUid) : "";
    if (!payeeUid) {
      return;
    }
    let email = "";
    try {
      const u = await db.doc("users/" + payeeUid).get();
      if (u.exists) {
        const em = u.get("email");
        if (em != null) {
          email = String(em).trim().toLowerCase();
        }
      }
    } catch (e) {
      console.error("onExpensePaymentClaimCreatedEmail: user read failed", e);
    }
    if (!email) {
      console.warn("onExpensePaymentClaimCreatedEmail: no email for uid", payeeUid);
      return;
    }
    const cur = d.currency != null ? String(d.currency) : "";
    const total = d.totalAmount != null ? Number(d.totalAmount) : 0;
    const ids = Array.isArray(d.expenseIds) ? d.expenseIds : [];
    const n = ids.length;
    const preview = d.expenseTitlePreview != null ? String(d.expenseTitlePreview) : "";
    const claimId = String(event.params.claimId || "");
    const {careGroupId} = event.params;
    let groupName = "your care team";
    try {
      const g = await db.doc("careGroups/" + careGroupId).get();
      if (g.exists) {
        const gd = g.data() || {};
        const gn = (gd.name && String(gd.name).trim()) ||
          (gd.displayName && String(gd.displayName).trim()) || "";
        if (gn) {
          groupName = gn;
        }
      }
    } catch (_) {
      // ignore
    }
    const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const subj = "CareShare · Expenses paid · " + groupName;
    const textBody =
      String(n) + " expense(s) you submitted for \"" + groupName + "\" have been marked as paid in CareShare.\n\n" +
      "Total: " + cur + " " + String(total) + "\n" +
      "Claim reference: " + claimId + "\n\n" +
      (preview ? "Items (preview): " + preview + "\n\n" : "") +
      "— CareShare";
    const htmlBody =
      "<p><strong>" + esc(String(n)) + " expense(s)</strong> you submitted for <strong>" + esc(groupName) +
      "</strong> have been marked as <strong>paid</strong> in CareShare.</p>" +
      "<p>Total: <strong>" + esc(cur) + " " + esc(String(total)) + "</strong></p>" +
      "<p>Claim reference: <code>" + esc(claimId) + "</code></p>" +
      (preview ? "<p style=\"font-size:13px;color:#444;\">" + esc(preview) + "</p>" : "") +
      "<p style=\"color:#666;font-size:12px;\">Open the CareShare app for full details.</p>";
    try {
      await sendTransactionalResendEmail({
        to: email,
        subject: subj,
        textBody: textBody,
        htmlBody: htmlBody,
      });
    } catch (e) {
      console.error("onExpensePaymentClaimCreatedEmail: send failed", String((e && e.message) || e));
    }
  }
);

/**
 * @param {string|undefined} s
 * @return {boolean}
 */
function taskStatusIsDone(s) {
  if (s == null) {
    return false;
  }
  const t = String(s).toLowerCase();
  return t === "done" || t === "completed";
}

/**
 * +1 kudos to the member who completed the task (see [completedBy] on the task doc).
 * Firestore rules block direct client updates to [kudosScore] on members.
 */
exports.onCareGroupTaskCompletedKudos = onDocumentUpdated(
  {
    document: "careGroups/{careGroupId}/tasks/{taskId}",
    region: "us-central1",
  },
  async (event) => {
    const be = event.data.before;
    const af = event.data.after;
    if (!af.exists) {
      return;
    }
    const b = be.exists ? (be.data() || {}) : {};
    const a = af.data() || {};
    if (taskStatusIsDone(b.status) || !taskStatusIsDone(a.status)) {
      return;
    }
    const uid = a.completedBy != null ? String(a.completedBy).trim() : "";
    if (!uid) {
      return;
    }
    const {careGroupId} = event.params;
    const memRef = db.doc("careGroups/" + careGroupId + "/members/" + uid);
    let snap;
    try {
      snap = await memRef.get();
    } catch (e) {
      console.error("onCareGroupTaskCompletedKudos: member read failed", e);
      return;
    }
    if (!snap.exists) {
      console.warn("onCareGroupTaskCompletedKudos: no members doc for uid", uid);
      return;
    }
    try {
      await memRef.update({kudosScore: FieldValue.increment(1)});
    } catch (e) {
      console.error("onCareGroupTaskCompletedKudos: kudos update failed", e);
    }
  }
);

const {syncToGoogleCalendar} = require("./gcal/syncToGoogleCalendar");
const {syncInboundGoogleCalendar} = require("./gcal/syncInboundGoogleCalendar");
exports.syncToGoogleCalendar = syncToGoogleCalendar;
exports.syncInboundGoogleCalendar = syncInboundGoogleCalendar;

const altEmail = require("./altEmailVerification");
exports.sendAlternateEmailVerification = altEmail.sendAlternateEmailVerification;
exports.confirmAlternateEmailVerification = altEmail.confirmAlternateEmailVerification;

const chatNotifications = require("./chatNotifications");
exports.onChatMessageCreated = chatNotifications.onChatMessageCreated;

const medSched = require("./medicationReminderScheduler");
exports.scheduledMedicationReminders = medSched.scheduledMedicationReminders;

const medMissed = require("./medicationMissedPrincipals");
exports.scheduledMedicationMissedPrincipalAlerts =
  medMissed.scheduledMedicationMissedPrincipalAlerts;
