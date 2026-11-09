const test = require("node:test");
const assert = require("node:assert/strict");
const {
  extractNationalIdFields,
  extractText,
  parseNationalIdFields,
} = require("../src/gemini_national_id_client");

const expectedFields = {
  name: "Marie",
  surname: "Dupont",
  dateOfBirth: "1990-04-23",
  placeOfBirth: "Lyon",
};

test("extracts JSON text from a Gemini candidate", () => {
  assert.equal(
    extractText({
      candidates: [{ content: { parts: [{ text: '{"name":"Marie"}' }] } }],
    }),
    '{"name":"Marie"}',
  );
});

test("validates and normalizes national ID fields", () => {
  assert.deepEqual(parseNationalIdFields(JSON.stringify(expectedFields)), {
    ...expectedFields,
  });
  assert.deepEqual(
    parseNationalIdFields(
      '{"name":"Marie","surname":"","dateOfBirth":"","placeOfBirth":""}',
    ),
    {
      name: "Marie",
      surname: null,
      dateOfBirth: null,
      placeOfBirth: null,
    },
  );
  assert.throws(() =>
    parseNationalIdFields(
      '{"name":"Marie","surname":"Dupont","dateOfBirth":"1990-02-31",' +
        '"placeOfBirth":"Lyon"}',
    ),
  );
  assert.throws(() =>
    parseNationalIdFields(
      '{"name":"Marie","surname":12,"dateOfBirth":"","placeOfBirth":""}',
    ),
  );
});

test("sends image to Gemini and returns the structured fields", async () => {
  let request;
  const result = await extractNationalIdFields({
    apiKey: "test-key",
    imageBase64: "AQID",
    mimeType: "image/jpeg",
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        json: async () => ({
          candidates: [
            {
              content: {
                parts: [{ text: JSON.stringify(expectedFields) }],
              },
            },
          ],
        }),
      };
    },
  });

  assert.deepEqual(result, expectedFields);
  assert.match(request.url, /models\/gemini-3\.8-flash:generateContent$/);
  assert.equal(request.options.headers["x-goog-api-key"], "test-key");
  const body = JSON.parse(request.options.body);
  assert.deepEqual(body.contents[0].parts[1].inlineData, {
    mimeType: "image/jpeg",
    data: "AQID",
  });
  assert.equal(body.generationConfig.responseMimeType, "application/json");
  assert.deepEqual(body.generationConfig.responseSchema.required, [
    "name",
    "surname",
    "dateOfBirth",
    "placeOfBirth",
  ]);
});

test("rejects unsuccessful and empty Gemini responses", async () => {
  await assert.rejects(
    extractNationalIdFields({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/jpeg",
      fetchImpl: async () => ({ ok: false, status: 503 }),
    }),
    /status 503/,
  );
  await assert.rejects(
    extractNationalIdFields({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/jpeg",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({ candidates: [] }),
      }),
    }),
    /no extraction text/,
  );
});
