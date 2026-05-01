const crypto = require("crypto");

/**
 * @param {import("luxon").DateTime} adjustedLocal
 * @return {string}
 */
function doseSlotKeyFromLuxon(adjustedLocal) {
  const d = adjustedLocal;
  return (
    d.toFormat("yyyy-LL-dd") +
    "_t_" +
    d.hour +
    "_" +
    String(d.minute).padStart(2, "0")
  );
}

/**
 * @param {string} careGroupDataId
 * @param {string} slotKey
 * @param {string[]} medicationIds
 * @return {string}
 */
function medicationAckDocId(careGroupDataId, slotKey, medicationIds) {
  const ids = [...medicationIds].map(String).sort();
  const raw = careGroupDataId + "|" + slotKey + "|" + ids.join(",");
  return crypto.createHash("sha256").update(raw, "utf8").digest("hex").slice(0, 40);
}

module.exports = {doseSlotKeyFromLuxon, medicationAckDocId};
