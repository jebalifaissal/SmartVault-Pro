const maxImageBytes = 6 * 1024 * 1024;
const allowedMimeTypes = new Set(["image/jpeg", "image/png"]);

function decodeImage({ imageBase64, mimeType }) {
  if (
    typeof imageBase64 !== "string" ||
    typeof mimeType !== "string" ||
    !allowedMimeTypes.has(mimeType) ||
    imageBase64.length === 0 ||
    imageBase64.length > Math.ceil(maxImageBytes / 3) * 4 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(imageBase64)
  ) {
    throw new Error("invalid-image");
  }

  const image = Buffer.from(imageBase64, "base64");
  if (
    image.length === 0 ||
    image.length > maxImageBytes ||
    image.toString("base64") !== imageBase64
  ) {
    throw new Error("invalid-image");
  }

  return { imageBase64, mimeType };
}

module.exports = { decodeImage };
