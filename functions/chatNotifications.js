const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const db = getFirestore();
const messaging = getMessaging();

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
      "careGroups/" + careGroupId + "/chatChannels/" + channelId,
    );
    let ch;
    try {
      ch = await chRef.get();
    } catch (e) {
      console.error("onChatMessageCreated: channel read failed", String(e && e.message ? e.message : e));
      return;
    }
    if (!ch.exists) {
      return;
    }
    const m = ch.data() || {};
    const memberUids = Array.isArray(m.memberUids) ? m.memberUids.map(String) : [];
    const channelName = m.name && String(m.name).trim() ? String(m.name).trim() : "Chat";
    if (memberUids.length === 0) {
      return;
    }

    let sSnap;
    try {
      sSnap = await db.doc("users/" + createdBy).get();
    } catch (e) {
      console.error("onChatMessageCreated: sender read failed", String(e && e.message ? e.message : e));
      sSnap = {exists: false};
    }
    const senderName = sSnap.exists
      ? String(sSnap.get("displayName") || "Someone").trim() || "Someone"
      : "Someone";
    const preview = text.length > 120 ? text.slice(0, 120) + "\u2026" : (text || "(message)");

    const messages = [];
    for (const uid of memberUids) {
      if (uid === createdBy) {
        continue;
      }
      let tokCol;
      try {
        tokCol = await db.collection("users/" + uid + "/devicePushTokens").get();
      } catch (e) {
        console.warn("onChatMessageCreated: tokens read failed uid=" + uid, String(e && e.message ? e.message : e));
        continue;
      }
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
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        });
      }
    }
    if (messages.length === 0) {
      return;
    }
    try {
      const res = await messaging.sendEach(messages);
      console.log(
        "onChatMessageCreated: sent=" + messages.length +
        " success=" + res.successCount +
        " fail=" + res.failureCount,
      );
      if (res.failureCount > 0 && Array.isArray(res.responses)) {
        const errs = res.responses
          .filter((r) => !r.success && r.error)
          .slice(0, 5)
          .map((r) => String(r.error.message || r.error));
        if (errs.length > 0) {
          console.warn("onChatMessageCreated: sample errors", errs.join(" | "));
        }
      }
    } catch (e) {
      console.error("onChatMessageCreated: sendEach failed", String(e && e.message ? e.message : e));
    }
  },
);
