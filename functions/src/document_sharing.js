const crypto = require("node:crypto");

const SHAREABLE_FIELDS = new Set([
  "category",
  "holderName",
  "firstName",
  "lastName",
  "documentNumber",
  "dateOfBirth",
  "placeOfBirth",
  "expirationDate",
]);

const ALLOWED_EXPIRATION_MINUTES = new Set([5, 15, 30, 60, 1440]);

function createShareToken() {
  const token = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  return { token, tokenHash };
}

function hashShareToken(token) {
  if (typeof token !== "string" || !/^[a-f0-9]{64}$/i.test(token)) {
    return null;
  }
  return crypto.createHash("sha256").update(token.toLowerCase()).digest("hex");
}

function sanitizeShareFields(fields) {
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
    throw new TypeError("Select at least one valid field to share.");
  }

  const sanitized = {};
  for (const [key, value] of Object.entries(fields)) {
    if (!SHAREABLE_FIELDS.has(key)) {
      throw new TypeError("The selected share fields are not supported.");
    }
    if (typeof value !== "string" || value.trim().length === 0) continue;
    const trimmed = value.trim();
    if (trimmed.length > 160) {
      throw new TypeError("A selected field exceeds the supported length.");
    }
    sanitized[key] = trimmed;
  }

  if (Object.keys(sanitized).length === 0) {
    throw new TypeError("Select at least one non-empty field to share.");
  }
  return sanitized;
}

function validateExpirationMinutes(value) {
  if (!Number.isInteger(value) || !ALLOWED_EXPIRATION_MINUTES.has(value)) {
    throw new TypeError("Choose a supported share duration.");
  }
  return value;
}

async function readActiveShare({
  firestore,
  token,
  nowMillis = Date.now(),
}) {
  const tokenHash = hashShareToken(token);
  if (tokenHash == null) return { status: "not-found" };

  const snapshot = await firestore
    .collection("documentShares")
    .where("tokenHash", "==", tokenHash)
    .limit(1)
    .get();
  if (snapshot.empty) return { status: "not-found" };

  const share = snapshot.docs[0];
  const data = share.data();
  if (data.expiresAt.toMillis() <= nowMillis) {
    await share.ref.delete();
    return { status: "expired" };
  }

  try {
    return { status: "active", fields: sanitizeShareFields(data.fields) };
  } catch {
    await share.ref.delete();
    return { status: "not-found" };
  }
}

module.exports = {
  SHAREABLE_FIELDS,
  createShareToken,
  hashShareToken,
  readActiveShare,
  sanitizeShareFields,
  validateExpirationMinutes,
};
