const test = require("node:test");
const assert = require("node:assert/strict");
const {
  analyzeDocument,
  extractResponseText,
  parseDocumentAnalysis,
} = require("../src/runware_client");

test("extracts text from a Runware caption response", () => {
  assert.equal(
    extractResponseText({
      data: [{ taskType: "caption", text: '{"category":"passport"}' }],
    }),
    '{"category":"passport"}',
  );
});

test("accepts supported document fields and validates dates", () => {
  assert.deepEqual(
    parseDocumentAnalysis(
      '{"category":"passport","confidence":0.91,' +
        '"holderName":"Léa Martin","documentNumber":"AB123456",' +
        '"expiryDate":"2032-02-14"}',
    ),
    {
      category: "passport",
      confidence: 0.91,
      holderName: "Léa Martin",
      documentNumber: "AB123456",
      expiryDate: "2032-02-14",
    },
  );
  assert.throws(() =>
    parseDocumentAnalysis(
      '{"category":"bank_card","confidence":0.9,"holderName":null,' +
        '"documentNumber":null,"expiryDate":null}',
    ),
  );
  assert.throws(() =>
    parseDocumentAnalysis(
      '{"category":"passport","confidence":2,"holderName":null,' +
        '"documentNumber":null,"expiryDate":null}',
    ),
  );
  assert.throws(() =>
    parseDocumentAnalysis(
      '{"category":"passport","confidence":0.9,"holderName":null,' +
        '"documentNumber":null,"expiryDate":"2032-02-31"}',
    ),
  );
});

test("sends the image to Runware's vision model and returns validated fields", async () => {
  let request;
  const result = await analyzeDocument({
    apiKey: "test-key",
    imageBase64: "AQID",
    mimeType: "image/png",
    taskUUID: "test-task",
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        json: async () => ({
          data: [
            {
              taskType: "caption",
              taskUUID: "test-task",
              text:
                '{"category":"identity","confidence":0.87,' +
                '"holderName":"Léa Martin","documentNumber":"A123",' +
                '"expiryDate":"2031-06-30"}',
            },
          ],
        }),
      };
    },
  });

  assert.deepEqual(result, {
    category: "identity",
    confidence: 0.87,
    holderName: "Léa Martin",
    documentNumber: "A123",
    expiryDate: "2031-06-30",
  });
  assert.equal(request.url, "https://api.runware.ai/v1");
  assert.equal(request.options.headers.Authorization, "test-key");
  const [body] = JSON.parse(request.options.body);
  assert.equal(body.taskType, "caption");
  assert.equal(body.taskUUID, "test-task");
  assert.equal(body.model, "runware:152@2");
  assert.equal(body.deliveryMethod, "sync");
  assert.equal(body.inputs.image, "data:image/png;base64,AQID");
  assert.match(body.prompt, /Return only a JSON object/);
});

test("rejects unsuccessful and empty Runware responses", async () => {
  await assert.rejects(
    analyzeDocument({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/jpeg",
      fetchImpl: async () => ({ ok: false, status: 503 }),
    }),
    /status 503/,
  );

  await assert.rejects(
    analyzeDocument({
      apiKey: "test-key",
      imageBase64: "AQID",
      mimeType: "image/jpeg",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({ data: [] }),
      }),
    }),
    /no analysis text/,
  );
});
