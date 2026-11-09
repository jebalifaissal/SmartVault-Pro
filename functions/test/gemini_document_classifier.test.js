const test = require("node:test");
const assert = require("node:assert/strict");
const {
  classifyDocument,
  extractText,
  parseDocumentType,
} = require("../src/gemini_document_classifier");

test("extracts Gemini text and accepts all supported document categories", () => {
  assert.equal(
    extractText({
      candidates: [
        { content: { parts: [{ text: '{"category":"CIN"}' }] } },
      ],
    }),
    '{"category":"CIN"}',
  );

  for (const category of [
    "CIN",
    "PASSPORT",
    "CERTIFICATE",
    "DRIVING_LICENSE",
    "OTHER",
  ]) {
    assert.deepEqual(parseDocumentType(JSON.stringify({ category })), {
      category,
    });
  }
});

test("rejects malformed or unsupported Gemini categories", () => {
  assert.throws(() => parseDocumentType("{not-json"));
  assert.throws(() => parseDocumentType('{"category":"BANK_CARD"}'));
  assert.throws(() => parseDocumentType('{"category":12}'));
});

test("sends the image and a classification-only prompt to Gemini", async () => {
  let request;
  const result = await classifyDocument({
    apiKey: "test-key",
    imageBase64: "AQID",
    mimeType: "image/png",
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        json: async () => ({
          candidates: [
            {
              content: {
                parts: [{ text: '{"category":"CIN"}' }],
              },
            },
          ],
        }),
      };
    },
  });

  assert.deepEqual(result, { category: "CIN" });
  assert.match(request.url, /models\/gemini-3\.8-flash:generateContent$/);
  assert.equal(request.options.headers["x-goog-api-key"], "test-key");
  const body = JSON.parse(request.options.body);
  assert.deepEqual(body.contents[0].parts[1].inlineData, {
    mimeType: "image/png",
    data: "AQID",
  });
  assert.equal(body.generationConfig.responseMimeType, "application/json");
  assert.deepEqual(body.generationConfig.responseSchema.properties.category.enum, [
    "CIN",
    "PASSPORT",
    "CERTIFICATE",
    "DRIVING_LICENSE",
    "OTHER",
  ]);
  assert.match(body.contents[0].parts[0].text, /Do not extract or return/);
});

test("rejects Gemini HTTP and empty-result errors", async () => {
  await assert.rejects(
    classifyDocument({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/png",
      fetchImpl: async () => ({ ok: false, status: 429 }),
    }),
    /status 429/,
  );
  await assert.rejects(
    classifyDocument({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/png",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({ candidates: [] }),
      }),
    }),
    /no classification text/,
  );
});
