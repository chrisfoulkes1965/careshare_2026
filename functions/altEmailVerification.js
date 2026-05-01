"use strict";

const crypto = require("crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineString} = require("firebase-functions/params");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

// Reuse the same env params as the invitation email path so we don't
// double-define them. They are defined in functions/index.js too — Firebase
// merges identical defineString() calls at deploy time.
const careshareAppUrl = defineString("CARESHARE_APP_URL", {
  default: "https://careshare-2026.web.app",
  description: "Public web app base URL, no trailing slash.",
});
const resendApiKey = defineString("RESEND_API_KEY", {
  default: "",
  description: "Resend API key (re_...). Empty = skip email.",
});
const resendFromEmail = defineString("RESEND_FROM_EMAIL", {
  default: "",
  description: "From address (verified in Resend or onboarding@resend.dev).",
});
const resendFromName = defineString("RESEND_FROM_NAME", {
  default: "CareShare",
  description: "From display name for Resend.",
});

const TOKEN_TTL_HOURS = 48;
const TOKEN_COLLECTION = "altEmailVerificationTokens";

function newToken() {
  // 32 bytes -> 64 hex chars; 48-hour validity. Use base64url for shorter URLs.
  return crypto.randomBytes(32).toString("base64url");
}

function escHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

async function sendVerificationEmail({to, displayName, verifyUrl}) {
  const apiKey = (resendApiKey.value() || "").trim();
  const from = (resendFromEmail.value() || "").trim();
  const fromName = (resendFromName.value() || "CareShare").trim() || "CareShare";
  if (!apiKey || !from) {
    throw new Error(
      "Email verification is not configured (RESEND_API_KEY / RESEND_FROM_EMAIL).",
    );
  }
  const fromHeader = fromName
    ? String(fromName).replace(/[\r\n<>]/g, " ").trim() + " <" + from + ">"
    : from;
  const greeting = displayName ? "Hi " + displayName : "Hello";
  const subject = "Verify your CareShare alternate email";
  const text =
    greeting + ",\n\n" +
    "We received a request to add this email address to your CareShare profile.\n\n" +
    "Click the link below to verify the address. The link expires in " +
    TOKEN_TTL_HOURS + " hours.\n\n" +
    verifyUrl + "\n\n" +
    "If you didn't request this, you can ignore the message.\n\n" +
    "— " + fromName;
  const html =
    "<p>" + escHtml(greeting) + ",</p>" +
    "<p>We received a request to add this email address to your CareShare profile.</p>" +
    "<p><a href=\"" + escHtml(verifyUrl) + "\">Verify this email address</a></p>" +
    "<p style=\"color:#666;font-size:12px;\">The link expires in " +
    TOKEN_TTL_HOURS + " hours. If you didn't request this you can ignore the message.</p>";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromHeader,
      to: [to],
      subject: subject,
      text: text,
      html: html,
    }),
  });
  if (res.status < 200 || res.status >= 300) {
    const t = await res.text();
    throw new Error("Resend HTTP " + res.status + ": " + t);
  }
}

/**
 * Generates a verification token and emails a link to the supplied alternate
 * email address. The caller must be authenticated; the address must already
 * appear in `users/{uid}.alternateEmails`.
 */
exports.sendAlternateEmailVerification = onCall(
  {region: "us-central1"},
  async (request) => {
    const auth = request.auth;
    if (!auth || !auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data || {};
    const rawEmail = (data.email != null ? String(data.email) : "").trim().toLowerCase();
    if (!rawEmail || !rawEmail.includes("@")) {
      throw new HttpsError("invalid-argument", "Valid email required.");
    }
    const db = getFirestore();
    const userRef = db.doc("users/" + auth.uid);
    const snap = await userRef.get();
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "Profile not found.");
    }
    const u = snap.data() || {};
    const alts = Array.isArray(u.alternateEmails) ? u.alternateEmails : [];
    const idx = alts.findIndex((e) => {
      if (!e || typeof e !== "object") {
        return false;
      }
      const a = (e.address != null ? String(e.address) : "").trim().toLowerCase();
      return a === rawEmail;
    });
    if (idx === -1) {
      throw new HttpsError(
        "failed-precondition",
        "Add the email to your profile first.",
      );
    }
    const existing = alts[idx];
    if (existing && existing.verified === true) {
      // Already verified — nothing to do.
      return {sent: false, alreadyVerified: true};
    }

    const token = newToken();
    const now = Date.now();
    const expiresAt = Timestamp.fromMillis(now + TOKEN_TTL_HOURS * 3600 * 1000);

    // Invalidate any earlier tokens for the same uid+email pair (best-effort).
    try {
      const prior = await db
        .collection(TOKEN_COLLECTION)
        .where("uid", "==", auth.uid)
        .where("email", "==", rawEmail)
        .where("usedAt", "==", null)
        .get();
      const batch = db.batch();
      for (const d of prior.docs) {
        batch.update(d.ref, {invalidatedAt: FieldValue.serverTimestamp()});
      }
      if (!prior.empty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore — old tokens just remain valid alongside the new one.
    }

    await db.collection(TOKEN_COLLECTION).doc(token).set({
      uid: auth.uid,
      email: rawEmail,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: expiresAt,
      usedAt: null,
    });

    // Update the alt-email entry to track when verification was sent.
    const updatedAlts = alts.slice();
    updatedAlts[idx] = Object.assign({}, existing, {
      lastVerificationSentAt: FieldValue.serverTimestamp(),
    });
    // FieldValue.serverTimestamp() inside an array element doesn't resolve —
    // fall back to Timestamp.now() so the array write is well-defined.
    updatedAlts[idx].lastVerificationSentAt = Timestamp.now();
    await userRef.update({alternateEmails: updatedAlts});

    const base = String(careshareAppUrl.value() || "https://careshare-2026.web.app").replace(/\/$/, "");
    const verifyUrl = base + "/verify-email?token=" + encodeURIComponent(token);

    const displayName = ((u.displayName != null ? String(u.displayName) : "") || "").trim();

    try {
      await sendVerificationEmail({
        to: rawEmail,
        displayName: displayName,
        verifyUrl: verifyUrl,
      });
    } catch (e) {
      const msg = String((e && e.message) || e).slice(0, 2000);
      console.error("sendAlternateEmailVerification: failed", msg);
      throw new HttpsError("internal", msg);
    }

    return {sent: true, expiresAt: expiresAt.toMillis()};
  }
);

/**
 * Validates a token from the verification link and marks the matching
 * `alternateEmails[i].verified = true`. Idempotent: re-clicking a used token
 * within TTL still returns the verified address.
 */
exports.confirmAlternateEmailVerification = onCall(
  {region: "us-central1"},
  async (request) => {
    const auth = request.auth;
    if (!auth || !auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data || {};
    const token = (data.token != null ? String(data.token) : "").trim();
    if (!token) {
      throw new HttpsError("invalid-argument", "Missing token.");
    }
    const db = getFirestore();
    const tokRef = db.collection(TOKEN_COLLECTION).doc(token);
    const tokSnap = await tokRef.get();
    if (!tokSnap.exists) {
      throw new HttpsError("not-found", "Verification link is invalid.");
    }
    const t = tokSnap.data() || {};
    const tUid = (t.uid != null ? String(t.uid) : "");
    const tEmail = ((t.email != null ? String(t.email) : "") || "").trim().toLowerCase();
    if (!tUid || !tEmail) {
      throw new HttpsError("not-found", "Verification link is invalid.");
    }
    if (tUid !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "Sign in with the account that requested this verification.",
      );
    }
    const exp = t.expiresAt;
    const expMs = exp instanceof Timestamp
      ? exp.toMillis()
      : (exp && typeof exp.toMillis === "function" ? exp.toMillis() : 0);
    if (expMs && Date.now() > expMs) {
      throw new HttpsError("deadline-exceeded", "Verification link has expired.");
    }

    const userRef = db.doc("users/" + tUid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "Profile not found.");
    }
    const u = userSnap.data() || {};
    const alts = Array.isArray(u.alternateEmails) ? u.alternateEmails : [];
    let found = false;
    const updated = alts.map((e) => {
      if (!e || typeof e !== "object") {
        return e;
      }
      const a = (e.address != null ? String(e.address) : "").trim().toLowerCase();
      if (a === tEmail) {
        found = true;
        return Object.assign({}, e, {
          verified: true,
          verifiedAt: Timestamp.now(),
        });
      }
      return e;
    });
    if (!found) {
      // Email was removed from the profile in between -> mark token used and error.
      try {
        await tokRef.update({usedAt: FieldValue.serverTimestamp()});
      } catch (_) {/* ignore */}
      throw new HttpsError(
        "failed-precondition",
        "That email is no longer on your profile.",
      );
    }
    await userRef.update({alternateEmails: updated});
    try {
      await tokRef.update({usedAt: FieldValue.serverTimestamp()});
    } catch (_) {/* ignore */}

    return {email: tEmail};
  }
);
