const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createShareToken,
  hashShareToken,
  readActiveShare,
  sanitizeShareFields,
  validateExpirationMinutes,
} = require("../src/document_sharing");

test("creates a high-entropy token and only exposes a one-way hash", () => {
  const first = createShareToken();
  const second = createShareToken();

  assert.match(first.token, /^[a-f0-9]{64}$/);
  assert.notEqual(first.token, first.tokenHash);
  assert.equal(hashShareToken(first.token), first.tokenHash);
  assert.notEqual(first.token, second.token);
  assert.equal(hashShareToken("not-a-token"), null);
});

test("only keeps explicitly supplied, non-empty shareable fields", () => {
  assert.deepEqual(
    sanitizeShareFields({
      firstName: "  Sana  ",
      lastName: "",
      documentNumber: "12345678",
    }),
    { firstName: "Sana", documentNumber: "12345678" },
  );
  assert.throws(() => sanitizeShareFields({ imagePath: "/private/cin.jpg" }));
  assert.throws(() => sanitizeShareFields({ firstName: "" }));
  assert.throws(() => sanitizeShareFields({ firstName: "x".repeat(161) }));
});

test("allows only supported temporary share durations", () => {
  for (const duration of [5, 15, 30, 60, 1440]) {
    assert.equal(validateExpirationMinutes(duration), duration);
  }
  for (const duration of [0, 10, 1441, "15"]) {
    assert.throws(() => validateExpirationMinutes(duration));
  }
});

test("validates active shares and rejects expired or revoked tokens", async () => {
  const { token, tokenHash } = createShareToken();
  let deleted = false;
  const activeDocument = {
    data: () => ({
      expiresAt: { toMillis: () => 2000 },
      fields: { firstName: "Sana" },
    }),
    ref: { delete: async () => { deleted = true; } },
  };
  const activeFirestore = makeFirestore(tokenHash, activeDocument);

  assert.deepEqual(
    await readActiveShare({
      firestore: activeFirestore,
      token,
      nowMillis: 1000,
    }),
    { status: "active", fields: { firstName: "Sana" } },
  );
  assert.equal(deleted, false);
  assert.deepEqual(
    await readActiveShare({
      firestore: activeFirestore,
      token,
      nowMillis: 2000,
    }),
    { status: "expired" },
  );
  assert.equal(deleted, true);
  assert.deepEqual(
    await readActiveShare({
      firestore: makeFirestore(null, null),
      token,
      nowMillis: 1000,
    }),
    { status: "not-found" },
  );
});

function makeFirestore(tokenHash, document) {
  return {
    collection: () => ({
      where: (_field, _operator, value) => ({
        limit: () => ({
          get: async () => {
            if (value !== tokenHash || document == null) {
              return { empty: true, docs: [] };
            }
            return { empty: false, docs: [document] };
          },
        }),
      }),
    }),
  };
}
