const test = require("node:test");
const assert = require("node:assert/strict");
const { decodeImage } = require("../src/image_validation");

test("accepts valid JPEG and PNG base64 images", () => {
  assert.deepEqual(decodeImage({ imageBase64: "AQID", mimeType: "image/jpeg" }), {
    imageBase64: "AQID",
    mimeType: "image/jpeg",
  });
  assert.deepEqual(decodeImage({ imageBase64: "AQID", mimeType: "image/png" }), {
    imageBase64: "AQID",
    mimeType: "image/png",
  });
});

test("rejects invalid image data and unsupported types", () => {
  assert.throws(() =>
    decodeImage({ imageBase64: "AQID", mimeType: "image/gif" }),
  );
  assert.throws(() =>
    decodeImage({ imageBase64: "not-base64", mimeType: "image/jpeg" }),
  );
  assert.throws(() =>
    decodeImage({ imageBase64: "", mimeType: "image/jpeg" }),
  );
});
