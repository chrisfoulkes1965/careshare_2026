const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const db = getFirestore();
const messaging = getMessaging();

const MISSED_GRACE_MS = 45 * 60 * 1000;

/**
 * Notifies principal carers / POA / group admins when a dose reminder was not confirmed
 * within [MISSED_GRACE_MS] of [dueAt].
 */
exports.scheduledMedicationMissedPrincipalAlerts = onSchedule(
  {
    schedule: "every 15 minutes",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - MISSED_GRACE_MS);
    let snap;
    try {
      snap = await db
        .collectionGroup("medicationReminderAcks")
        .where("needsConfirmation", "==", true)
        .where("principalAlertSent", "==", false)
        .where("dueAt", "<=", cutoff)
        .limit(80)
        .get();
    } catch (e) {
      console.error("medicationMissed query failed", String(e && e.message ? e.message : e));
      return;
    }

    let pushes = 0;
    for (const doc of snap.docs) {
      const cgRef = doc.ref.parent.parent;
      if (!cgRef) {
        continue;
      }
      const dataCareGroupId = cgRef.id;
      const d = doc.data() || {};
      const ids = Array.isArray(d.medicationIds) ? d.medicationIds.map(String) : [];
      const slotKey = d.slotKey != null ? String(d.slotKey) : "";

      let members;
      try {
        members = await db
          .collection("careGroups/" + dataCareGroupId + "/members")
          .get();
      } catch (e) {
        console.warn("medicationMissed members", dataCareGroupId, String(e));
        continue;
      }

      const principalUids = [];
      for (const m of members.docs) {
        const roles = m.get("roles");
        const rs = Array.isArray(roles) ? roles.map(String) : [];
        if (
          rs.includes("principal_carer") ||
          rs.includes("power_of_attorney") ||
          rs.includes("care_group_administrator")
        ) {
          principalUids.push(m.id);
        }
      }

      const messages = [];
      for (const puid of principalUids) {
        let tokCol;
        try {
          tokCol = await db.collection("users/" + puid + "/devicePushTokens").get();
        } catch (_) {
          continue;
        }
        for (const tdoc of tokCol.docs) {
          const token =
            tdoc.get("token") && String(tdoc.get("token")).trim()
              ? String(tdoc.get("token")).trim()
              : "";
          if (!token) {
            continue;
          }
          messages.push({
            token: token,
            notification: {
              title: "CareShare · Missed medication confirmation",
              body:
                "A scheduled dose was not confirmed on time. Open Meds to review.",
            },
            data: {
              type: "medicationMissed",
              careGroupId: String(dataCareGroupId),
              medicationIds: ids.join(","),
              slotKey: slotKey,
            },
            android: {
              notification: {
                channelId: "careshare_medications",
              },
            },
          });
        }
      }

      if (messages.length === 0) {
        try {
          await doc.ref.update({
            principalAlertSent: true,
            principalAlertSentAt: FieldValue.serverTimestamp(),
            principalAlertSkipReason: "no_tokens",
          });
        } catch (e) {
          console.warn("medicationMissed skip update", doc.id, String(e));
        }
        continue;
      }

      try {
        const res = await messaging.sendEach(messages);
        pushes += res.successCount;
        await doc.ref.update({
          principalAlertSent: true,
          principalAlertSentAt: FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.warn(
          "medicationMissed send",
          doc.id,
          String(e && e.message ? e.message : e)
        );
      }
    }

    console.log(
      "scheduledMedicationMissedPrincipalAlerts: scanned=" +
        snap.size +
        " pushes~" +
        pushes
    );
  },
);
