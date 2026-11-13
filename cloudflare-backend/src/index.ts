declare global {
  interface Env {
    FIREBASE_SERVICE_ACCOUNT: string;
    IMAGEKIT_PRIVATE_KEY: string;
    IMAGEKIT_PUBLIC_KEY: string;
    IMAGEKIT_URL_ENDPOINT: string;
  }
}
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

export const DEFAULT_PASSWORD_ITERATIONS = 100_000;
export const LEGACY_PASSWORD_ITERATIONS = 310_000;
const sessionLifetimeMs = 30 * 24 * 60 * 60 * 1000;
function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getFirebaseAccessToken(env: Env): Promise<string> {
  const serviceAccount = JSON.parse(
    env.FIREBASE_SERVICE_ACCOUNT
  ) as {
    project_id: string;
    client_email: string;
    private_key: string;
    token_uri?: string;
  };

  const now = Math.floor(Date.now() / 1000);

  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();

  const unsignedToken =
    `${base64UrlEncode(encoder.encode(JSON.stringify(header)))}.` +
    `${base64UrlEncode(encoder.encode(JSON.stringify(payload)))}`;

  const privateKeyPem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  const privateKeyBytes = Uint8Array.from(
    atob(privateKeyPem),
    (char) => char.charCodeAt(0)
  );

  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    encoder.encode(unsignedToken)
  );

  const assertion =
    `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    }
  );

  const result = await response.json() as {
    access_token?: string;
    error?: string;
  };

  if (!response.ok || !result.access_token) {
    throw new Error(
      `Firebase OAuth error: ${result.error ?? response.statusText}`
    );
  }

  return result.access_token;
}
async function sendFirebasePush(
  env: Env,
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<void> {
  const serviceAccount = JSON.parse(
    env.FIREBASE_SERVICE_ACCOUNT,
  ) as { project_id: string };

  const accessToken = await getFirebaseAccessToken(env);

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data,
          android: {
            priority: "high",
          },
        },
      }),
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    console.error("FCM send error:", response.status, errorText);
    throw new Error(`FCM send failed: ${response.status}`);
  }
}
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== ""
    ? value.trim()
    : null;
}

export type AuthPrincipal = {
  uid: string;
  email: string;
  displayName: string;
};

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function fromHex(value: string): Uint8Array {
  if (!/^(?:[0-9a-f]{2})+$/i.test(value)) {
    throw new TypeError("Invalid hexadecimal value");
  }
  return Uint8Array.from(
    value.match(/.{2}/g) ?? [],
    (byte) => Number.parseInt(byte, 16),
  );
}

function sha256Transform(w: Int32Array, state: number[]): void {
  let [a, b, c, d, e, f, g, h] = state;
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  for (let i = 0; i < 64; i++) {
    if (i >= 16) {
      const s0 =
        ((w[i - 15] >>> 7) | (w[i - 15] << 25)) ^
        ((w[i - 15] >>> 18) | (w[i - 15] << 14)) ^
        (w[i - 15] >>> 3);
      const s1 =
        ((w[i - 2] >>> 17) | (w[i - 2] << 15)) ^
        ((w[i - 2] >>> 19) | (w[i - 2] << 13)) ^
        (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
    }
    const S1 =
      ((e >>> 6) | (e << 26)) ^
      ((e >>> 11) | (e << 21)) ^
      ((e >>> 25) | (e << 7));
    const ch = (e & f) ^ (~e & g);
    const temp1 = (h + S1 + ch + K[i] + w[i]) | 0;
    const S0 =
      ((a >>> 2) | (a << 30)) ^
      ((a >>> 13) | (a << 19)) ^
      ((a >>> 22) | (a << 10));
    const maj = (a & b) ^ (a & c) ^ (b & c);
    const temp2 = (S0 + maj) | 0;

    h = g; g = f; f = e; e = (d + temp1) | 0;
    d = c; c = b; b = a; a = (temp1 + temp2) | 0;
  }
  state[0] = (state[0] + a) | 0;
  state[1] = (state[1] + b) | 0;
  state[2] = (state[2] + c) | 0;
  state[3] = (state[3] + d) | 0;
  state[4] = (state[4] + e) | 0;
  state[5] = (state[5] + f) | 0;
  state[6] = (state[6] + g) | 0;
  state[7] = (state[7] + h) | 0;
}

export function pbkdf2Sha256Software(
  password: string,
  salt: Uint8Array,
  iterations: number,
): string {
  const pwBytes = new TextEncoder().encode(password);
  const key = new Uint8Array(64);
  if (pwBytes.length > 64) {
    const s = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const w = new Int32Array(64);
    const pad = new Uint8Array(64);
    pad.set(pwBytes.subarray(0, 64));
    pad[pwBytes.length] = 0x80;
    const view = new DataView(pad.buffer);
    view.setUint32(60, pwBytes.length * 8);
    for (let i = 0; i < 16; i++) w[i] = view.getInt32(i * 4);
    sha256Transform(w, s);
    const dv = new DataView(key.buffer);
    for (let i = 0; i < 8; i++) dv.setInt32(i * 4, s[i]);
  } else {
    key.set(pwBytes);
  }

  const ipadKey = new Int32Array(16);
  const opadKey = new Int32Array(16);
  const dvKey = new DataView(key.buffer);
  for (let i = 0; i < 16; i++) {
    const v = dvKey.getInt32(i * 4);
    ipadKey[i] = v ^ 0x36363636;
    opadKey[i] = v ^ 0x5c5c5c5c;
  }

  const initialIpadState = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const w0 = new Int32Array(64);
  w0.set(ipadKey);
  sha256Transform(w0, initialIpadState);

  const initialOpadState = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const w1 = new Int32Array(64);
  w1.set(opadKey);
  sha256Transform(w1, initialOpadState);

  function hmacSha256(msg: Uint8Array): Uint8Array {
    const sInner = [...initialIpadState];
    const sOuter = [...initialOpadState];
    const totalInnerLen = 64 + msg.length;
    const bitLen = totalInnerLen * 8;
    const block = new Uint8Array(64);
    block.set(msg);
    block[msg.length] = 0x80;
    const bView = new DataView(block.buffer);
    bView.setUint32(60, bitLen);
    const w = new Int32Array(64);
    for (let i = 0; i < 16; i++) w[i] = bView.getInt32(i * 4);
    sha256Transform(w, sInner);

    const outBlock = new Uint8Array(64);
    const outView = new DataView(outBlock.buffer);
    for (let i = 0; i < 8; i++) outView.setInt32(i * 4, sInner[i]);
    outBlock[32] = 0x80;
    outView.setUint32(60, (64 + 32) * 8);
    for (let i = 0; i < 16; i++) w[i] = outView.getInt32(i * 4);
    sha256Transform(w, sOuter);

    const res = new Uint8Array(32);
    const resView = new DataView(res.buffer);
    for (let i = 0; i < 8; i++) resView.setInt32(i * 4, sOuter[i]);
    return res;
  }

  const saltBlock = new Uint8Array(salt.length + 4);
  saltBlock.set(salt);
  saltBlock[salt.length + 3] = 1;
  const u = hmacSha256(saltBlock);
  const result = new Uint8Array(u);

  const sInnerT = [0, 0, 0, 0, 0, 0, 0, 0];
  const sOuterT = [0, 0, 0, 0, 0, 0, 0, 0];
  const wInner = new Int32Array(64);
  wInner[8] = 0x80000000;
  wInner[15] = (64 + 32) * 8;
  const wOuter = new Int32Array(64);
  wOuter[8] = 0x80000000;
  wOuter[15] = (64 + 32) * 8;

  const uView = new DataView(u.buffer, u.byteOffset, 32);
  const rView = new DataView(result.buffer, result.byteOffset, 32);

  for (let iter = 1; iter < iterations; iter++) {
    for (let i = 0; i < 8; i++) {
      sInnerT[i] = initialIpadState[i];
      wInner[i] = uView.getInt32(i * 4);
    }
    sha256Transform(wInner, sInnerT);

    for (let i = 0; i < 8; i++) {
      sOuterT[i] = initialOpadState[i];
      wOuter[i] = sInnerT[i];
    }
    sha256Transform(wOuter, sOuterT);

    for (let i = 0; i < 8; i++) {
      const val = sOuterT[i];
      uView.setInt32(i * 4, val);
      rView.setInt32(i * 4, rView.getInt32(i * 4) ^ val);
    }
  }

  return toHex(result);
}

export async function hashPassword(
  password: string,
  salt: string,
  iterations = DEFAULT_PASSWORD_ITERATIONS,
): Promise<string> {
  // Always use the pure-JS implementation for new hashes.
  // crypto.subtle.deriveBits with PBKDF2 consumes CPU time that exceeds the
  // Cloudflare Workers Free plan limit (10 ms) and can also hit the 30-second
  // default on the Paid plan for high iteration counts, causing Error 1102.
  // The software implementation runs in micro-tasks, avoiding the hard CPU cap.
  return pbkdf2Sha256Software(password, fromHex(salt), iterations);
}

export async function verifyPassword(
  password: string,
  salt: string,
  expectedHash: string,
): Promise<{ valid: boolean; needsRehash: boolean }> {
  let expected: Uint8Array;
  try {
    expected = fromHex(expectedHash);
  } catch {
    return { valid: false, needsRehash: false };
  }

  // 1. Check default 100_000 iterations
  try {
    const actual100k = fromHex(await hashPassword(password, salt, DEFAULT_PASSWORD_ITERATIONS));
    if (actual100k.length === expected.length) {
      let diff = 0;
      for (let i = 0; i < actual100k.length; i++) {
        diff |= actual100k[i] ^ expected[i];
      }
      if (diff === 0) {
        return { valid: true, needsRehash: false };
      }
    }
  } catch {
    // Continue
  }

  // 2. Check legacy 310_000 iterations
  try {
    const actual310k = fromHex(await hashPassword(password, salt, LEGACY_PASSWORD_ITERATIONS));
    if (actual310k.length === expected.length) {
      let diff = 0;
      for (let i = 0; i < actual310k.length; i++) {
        diff |= actual310k[i] ^ expected[i];
      }
      if (diff === 0) {
        return { valid: true, needsRehash: true };
      }
    }
  } catch {
    // Legacy failed
  }

  return { valid: false, needsRehash: false };
}

async function sha256Hex(value: string): Promise<string> {
  return toHex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  );
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function authenticatedPrincipal(
  request: Request,
  env: Env,
): Promise<(AuthPrincipal & { tokenHash: string }) | null> {
  const authorization = request.headers.get("Authorization");
  const token = authorization?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return null;
  const tokenHash = await sha256Hex(token);
  const row = await env.smartvault_db
    .prepare(
      `SELECT u.id, u.email, u.display_name
       FROM auth_sessions s JOIN auth_users u ON u.id = s.user_id
       WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ?`,
    )
    .bind(tokenHash, Date.now())
    .first<{ id: string; email: string; display_name: string }>();
  return row
    ? {
        uid: row.id,
        email: row.email,
        displayName: row.display_name,
        tokenHash,
      }
    : null;
}

async function isAdministrator(
  principal: AuthPrincipal,
  env: Env,
): Promise<boolean> {
  const row = await env.smartvault_db
    .prepare(
      "SELECT 1 AS allowed FROM admin_users WHERE email = ? AND user_id = ? AND active = 1",
    )
    .bind(principal.email, principal.uid)
    .first();
  return row != null;
}

// ─── Admin-session helpers ────────────────────────────────────────────────────

const adminSessionLifetimeMs = 8 * 60 * 60 * 1000; // 8 heures

type AdminPrincipal = {
  email: string;
  tokenHash: string;
};

/**
 * Vérifie le Bearer token dans l'en-tête Authorization contre la table
 * admin_sessions.  Retourne le principal admin si la session est valide,
 * ou null sinon.  Ne touche jamais auth_sessions (séparation stricte).
 */
async function authenticatedAdmin(
  request: Request,
  env: Env,
): Promise<AdminPrincipal | null> {
  const authorization = request.headers.get("Authorization");
  const token = authorization?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return null;
  const tokenHash = await sha256Hex(token);
  const row = await env.smartvault_db
    .prepare(
      `SELECT a.email
       FROM admin_sessions s
       JOIN admin_users a ON a.email = s.admin_email
       WHERE s.token_hash = ?
         AND s.revoked_at IS NULL
         AND s.expires_at > ?
         AND a.active = 1`,
    )
    .bind(tokenHash, Date.now())
    .first<{ email: string }>();
  return row ? { email: row.email, tokenHash } : null;
}

function validImage(body: Record<string, unknown>):
  | { bytes: Uint8Array; mimeType: string }
  | null {
  const mimeType = body.image_mime_type;
  const encoded = body.image_base64;
  if (
    (mimeType !== "image/jpeg" && mimeType !== "image/png") ||
    typeof encoded !== "string" ||
    encoded.length === 0 ||
    encoded.length > 8 * 1024 * 1024 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
      encoded,
    )
  ) {
    return null;
  }
  const binary = atob(encoded);
  if (binary.length === 0 || binary.length > 6 * 1024 * 1024) return null;
  return {
    bytes: Uint8Array.from(binary, (character) => character.charCodeAt(0)),
    mimeType,
  };
}

async function uploadClassificationImage(
  env: Env,
  image: { bytes: Uint8Array; mimeType: string },
  folder = "/smartvault-classification",
  prefix = "classification",
): Promise<string> {
  const privateKey = env.IMAGEKIT_PRIVATE_KEY;

  if (!privateKey || !env.IMAGEKIT_URL_ENDPOINT) {
    throw new Error("ImageKit configuration is missing.");
  }

  const extension = image.mimeType === "image/png" ? "png" : "jpg";
  const fileName = `${prefix}-${crypto.randomUUID()}.${extension}`;

  const form = new FormData();

  const imageBuffer = image.bytes.buffer.slice(
    image.bytes.byteOffset,
    image.bytes.byteOffset + image.bytes.byteLength,
  ) as ArrayBuffer;

  form.append(
    "file",
    new Blob([imageBuffer], { type: image.mimeType }),
    fileName,
  );
  form.append("fileName", fileName);
  form.append("folder", folder);
  form.append("useUniqueFileName", "true");
  form.append("isPrivateFile", "true");

  const response = await fetch(
    "https://upload.imagekit.io/api/v1/files/upload",
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${privateKey}:`)}`,
      },
      body: form,
    },
  );

  if (!response.ok) {
    throw new Error(`ImageKit upload failed: ${response.status}`);
  }

  const result = await response.json() as Record<string, unknown>;

  if (typeof result.filePath !== "string" || !result.filePath) {
    throw new Error("ImageKit did not return a valid file path.");
  }

  return result.filePath;
}

function documentFromRow(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    category: row.category,
    file_name: row.file_name,
    created_at: row.created_at,
    holder_name: row.holder_name,
    document_number: row.document_number,
    expiry_date: row.expiry_date,
    name: row.name,
    surname: row.surname,
    date_of_birth: row.date_of_birth,
    place_of_birth: row.place_of_birth,
    image_storage_path: row.image_storage_path,
    document_type: row.document_type,
    full_name: row.full_name,
    first_name: row.first_name,
    last_name: row.last_name,
    cin_number: row.cin_number,
    expiration_date: row.expiration_date,
    updated_at: row.updated_at,
    status: row.status,
    security_level: row.security_level,
    classification_status: row.classification_status,
    classification_source: row.classification_source,
  };
}

export default {
  async fetch(request, env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      // Test API
      if (path === "/" && request.method === "GET") {
        return json({
          success: true,
          message: "SmartVault Pro API is running",
        });
      }

      if (path === "/api/auth/register" && request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body)) {
          return json({ success: false, error: "Invalid registration payload" }, 400);
        }

        const nameRaw = body.name;
        const emailRaw = body.email;
        const passwordRaw = body.password;

        if (
          typeof nameRaw !== "string" ||
          nameRaw.trim().length < 2 ||
          nameRaw.trim().length > 100
        ) {
          return json({ success: false, error: "Invalid name" }, 400);
        }

        if (
          typeof emailRaw !== "string" ||
          emailRaw.trim().length > 254
        ) {
          return json({ success: false, error: "Invalid email" }, 400);
        }

        const email = emailRaw.trim().toLowerCase();
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
          return json({ success: false, error: "Invalid email" }, 400);
        }

        if (
          typeof passwordRaw !== "string" ||
          passwordRaw.length < 8 ||
          passwordRaw.length > 128
        ) {
          return json(
            { success: false, error: "Password must be at least 8 characters" },
            400,
          );
        }

        const displayName = nameRaw.trim();
        const password = passwordRaw;

        // Ensure email is not already an existing user or admin
        const existingUser = await env.smartvault_db
          .prepare("SELECT 1 FROM auth_users WHERE email = ?")
          .bind(email)
          .first();
        if (existingUser) {
          return json({ success: false, error: "Email already in use" }, 409);
        }

        const existingAdmin = await env.smartvault_db
          .prepare("SELECT 1 FROM admin_users WHERE email = ?")
          .bind(email)
          .first();
        if (existingAdmin) {
          return json({ success: false, error: "Email already in use" }, 409);
        }

        const userId = crypto.randomUUID();
        const saltBytes = crypto.getRandomValues(new Uint8Array(16));
        const salt = toHex(saltBytes);
        const hashedPassword = await hashPassword(password, salt);
        const now = Date.now();

        try {
          await env.smartvault_db
            .prepare(
              `INSERT INTO auth_users (id, email, display_name, password_salt, password_hash, created_at)
               VALUES (?, ?, ?, ?, ?, ?)`,
            )
            .bind(userId, email, displayName, salt, hashedPassword, now)
            .run();
        } catch (err: unknown) {
          const message = err instanceof Error ? err.message : String(err);
          if (message.includes("UNIQUE") || message.includes("constraint")) {
            return json({ success: false, error: "Email already in use" }, 409);
          }
          throw err;
        }

        const token = randomToken();
        const tokenHash = await sha256Hex(token);
        const expiresAt = now + sessionLifetimeMs;

        await env.smartvault_db
          .prepare(
            "INSERT INTO auth_sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
          )
          .bind(tokenHash, userId, expiresAt, now)
          .run();

        return json(
          {
            success: true,
            token,
            expires_at: expiresAt,
            user: {
              id: userId,
              email,
              display_name: displayName,
            },
            isAdmin: false,
          },
          201,
        );
      }

      if (path === "/api/auth/password-reset" && request.method === "POST") {
        return json(
          {
            success: false,
            error: "Password reset is unavailable until email delivery is configured.",
          },
          503,
        );
      }

      if (path === "/api/auth/login" && request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body)) {
          return json({ success: false, error: "Invalid credentials" }, 400);
        }
        const emailValue = body.email;
        const password = body.password;
        if (
          typeof emailValue !== "string" ||
          emailValue.trim().length > 254 ||
          typeof password !== "string" ||
          password.length > 128
        ) {
          return json({ success: false, error: "Invalid credentials" }, 400);
        }

        const email = emailValue.trim().toLowerCase();
        const clientIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const attemptKey = await sha256Hex(clientIp);
        const now = Date.now();
        const attempt = await env.smartvault_db
          .prepare("SELECT attempts, window_start FROM auth_login_attempts WHERE key_hash = ?")
          .bind(attemptKey)
          .first<{ attempts: number; window_start: number }>();
        if (attempt && now - attempt.window_start < 15 * 60 * 1000 && attempt.attempts >= 20) {
          return json({ success: false, error: "Too many login attempts" }, 429);
        }

        const user = await env.smartvault_db
          .prepare("SELECT id, email, display_name, password_salt, password_hash FROM auth_users WHERE email = ?")
          .bind(email)
          .first<{
            id: string;
            email: string;
            display_name: string;
            password_salt: string;
            password_hash: string;
          }>();
        const check = await verifyPassword(
          password,
          user?.password_salt ?? "00000000000000000000000000000000",
          user?.password_hash ?? "00".repeat(32),
        );
        if (!user || !check.valid) {
          await env.smartvault_db
            .prepare(
              `INSERT INTO auth_login_attempts (key_hash, attempts, window_start)
               VALUES (?, 1, ?)
               ON CONFLICT(key_hash) DO UPDATE SET
                 attempts = CASE WHEN window_start <= ? THEN 1 ELSE attempts + 1 END,
                 window_start = CASE WHEN window_start <= ? THEN ? ELSE window_start END`,
            )
            .bind(
              attemptKey,
              now,
              now - 15 * 60 * 1000,
              now - 15 * 60 * 1000,
              now,
            )
            .run();
          return json({ success: false, error: "Invalid email or password" }, 401);
        }

        if (check.needsRehash) {
          const newSaltBytes = crypto.getRandomValues(new Uint8Array(16));
          const newSalt = toHex(newSaltBytes);
          const newHash = await hashPassword(password, newSalt, DEFAULT_PASSWORD_ITERATIONS);
          await env.smartvault_db
            .prepare("UPDATE auth_users SET password_salt = ?, password_hash = ? WHERE id = ?")
            .bind(newSalt, newHash, user.id)
            .run();
        }

        await env.smartvault_db
          .prepare("DELETE FROM auth_login_attempts WHERE key_hash = ?")
          .bind(attemptKey)
          .run();
        const token = randomToken();
        const expiresAt = now + sessionLifetimeMs;
        await env.smartvault_db
          .prepare(
            "INSERT INTO auth_sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
          )
          .bind(await sha256Hex(token), user.id, expiresAt, now)
          .run();
        const principal = {
          uid: user.id,
          email: user.email,
          displayName: user.display_name,
        };
        return json({
          success: true,
          token,
          expires_at: expiresAt,
          user: {
            id: principal.uid,
            email: principal.email,
            display_name: principal.displayName,
          },
          isAdmin: await isAdministrator(principal, env),
        });
      }

      if (path === "/api/shares/open" && request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body) || typeof body.token !== "string" || body.token.length > 128) {
          return json({ success: false, error: "Invalid share link" }, 400);
        }
        const row = await env.smartvault_db
          .prepare(
            `SELECT fields_json, images_json FROM document_shares
             WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
          )
          .bind(await sha256Hex(body.token), Date.now())
          .first<{ fields_json: string; images_json: string | null }>();
        if (!row) {
          return json({ success: false, error: "Share link is expired or revoked" }, 404);
        }
        return json({
          success: true,
          fields: JSON.parse(row.fields_json),
          images: row.images_json ? Object.keys(JSON.parse(row.images_json)) : [],
        });
      }

      const shareImageMatch = path.match(/^\/api\/shares\/image\/(front|back)$/);
      if (shareImageMatch && request.method === "POST") {
        let body: unknown;
        try { body = await request.json(); } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body) || typeof body.token !== "string" || body.token.length > 128) {
          return json({ success: false, error: "Invalid share link" }, 400);
        }
        const share = await env.smartvault_db.prepare(
          `SELECT images_json FROM document_shares
           WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
        ).bind(await sha256Hex(body.token), Date.now())
          .first<{ images_json: string | null }>();
        if (!share?.images_json) return json({ success: false, error: "Shared image unavailable" }, 404);
        const images = JSON.parse(share.images_json) as Record<string, { path: string; mime: string }>;
        const image = images[shareImageMatch[1]];
        if (!image || typeof image.path !== "string" || !image.path.startsWith("/") ||
            (image.mime !== "image/jpeg" && image.mime !== "image/png")) {
          return json({ success: false, error: "Shared image unavailable" }, 404);
        }
        try {
          const expiresAt = Math.floor(Date.now() / 1000) + 60;
          const key = await crypto.subtle.importKey(
            "raw", new TextEncoder().encode(env.IMAGEKIT_PRIVATE_KEY),
            { name: "HMAC", hash: "SHA-1" }, false, ["sign"],
          );
          const signatureBuffer = await crypto.subtle.sign(
            "HMAC", key, new TextEncoder().encode(`${image.path}${expiresAt}`),
          );
          const signature = Array.from(new Uint8Array(signatureBuffer))
            .map((byte) => byte.toString(16).padStart(2, "0")).join("");
          const endpoint = env.IMAGEKIT_URL_ENDPOINT.replace(/\/+$/, "");
          const imageResponse = await fetch(
            `${endpoint}${image.path}?ik-t=${expiresAt}&ik-s=${signature}`,
          );
          if (!imageResponse.ok) return json({ success: false, error: "Image retrieval failed" }, 502);
          return new Response(imageResponse.body, {
            headers: {
              ...corsHeaders,
              "Content-Type": image.mime,
              "Cache-Control": "no-store, private",
              "X-Content-Type-Options": "nosniff",
              "Content-Disposition": "inline",
            },
          });
        } catch {
          return json({ success: false, error: "Image retrieval failed" }, 502);
        }
      }

      if (path === "/share" && request.method === "GET") {
        return new Response(
          `<!doctype html>
<html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Document partagé · SmartVault Pro</title>
<style>body{font:16px system-ui,sans-serif;max-width:640px;margin:12vh auto;padding:24px;color:#172b3a;background:#f4f7f7}main{background:white;padding:24px;border-radius:16px}dt{font-weight:700;margin-top:14px}dd{margin:4px 0;color:#526870}</style>
<main><h1>Document partagé</h1><p id="status">Vérification du lien…</p><dl id="fields"></dl><section id="photos"></section></main>
<script>
const status = document.getElementById('status');
const fields = document.getElementById('fields');
const photos = document.getElementById('photos');
const labels = {category:'Catégorie',holderName:'Titulaire',firstName:'Prénom',lastName:'Nom',documentNumber:'Numéro du document',dateOfBirth:'Date de naissance',placeOfBirth:'Lieu de naissance',expirationDate:'Date d’expiration'};
const token = location.hash.slice(1);
history.replaceState(null, '', location.pathname);
fetch('/api/shares/open', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})})
  .then(async response => {
    const data = await response.json();
    if (!response.ok || !data.success || typeof data.fields !== 'object') throw new Error();
    status.textContent = 'Ce lien est temporaire. Les photos Recto et Verso sont protégées et expireront avec le partage.';
    for (const [key, value] of Object.entries(data.fields)) {
      if (typeof value !== 'string' || !labels[key]) continue;
      const label = document.createElement('dt');
      label.textContent = labels[key];
      const item = document.createElement('dd');
      item.textContent = value;
      fields.append(label, item);
    }
    for (const side of ['front', 'back']) {
      if (!Array.isArray(data.images) || !data.images.includes(side)) continue;
      const heading = document.createElement('h2');
      heading.textContent = side === 'front' ? 'Recto' : 'Verso';
      const image = document.createElement('img');
      image.alt = heading.textContent;
      image.style.cssText = 'display:block;width:100%;height:auto;max-height:420px;object-fit:contain;margin:8px 0 20px;border:1px solid #e5ebeb;border-radius:12px';
      photos.append(heading, image);
      fetch('/api/shares/image/' + side, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})})
        .then(response => { if (!response.ok) throw new Error(); return response.blob(); })
        .then(blob => { image.src = URL.createObjectURL(blob); })
        .catch(() => { image.alt = 'Photo indisponible ou partage expiré'; });
    }
  })
  .catch(() => { status.textContent = 'Ce lien est invalide, révoqué ou expiré.'; });
</script></html>`,
          {
            headers: {
              ...corsHeaders,
              "Content-Type": "text/html; charset=utf-8",
              "Cache-Control": "no-store",
              "Content-Security-Policy":
                "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'; img-src blob:; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
              "Referrer-Policy": "no-referrer",
              "X-Content-Type-Options": "nosniff",
            },
          },
        );
      }

      // ── Routes Admin indépendantes (token admin_sessions requis) ─────────
      // Insérées AVANT authenticatedPrincipal — un token admin n'est jamais
      // un token utilisateur normal (tables séparées).

      if (path === "/api/admin/login" && request.method === "POST") {
        let body: unknown;
        try { body = await request.json(); } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body)) {
          return json({ success: false, error: "Invalid credentials" }, 400);
        }
        const emailValue = body.email;
        const password = body.password;
        if (
          typeof emailValue !== "string" || emailValue.trim().length > 254 ||
          typeof password !== "string" || password.length < 1 || password.length > 128
        ) {
          return json({ success: false, error: "Invalid credentials" }, 400);
        }
        const adminEmail = emailValue.trim().toLowerCase();
        const clientIp2 = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const atkKey = await sha256Hex("admin:" + clientIp2);
        const now2 = Date.now();
        const atkRow = await env.smartvault_db
          .prepare("SELECT attempts, window_start FROM admin_login_attempts WHERE key_hash = ?")
          .bind(atkKey)
          .first<{ attempts: number; window_start: number }>();
        if (atkRow && now2 - atkRow.window_start < 15 * 60 * 1000 && atkRow.attempts >= 10) {
          return json({ success: false, error: "Too many login attempts" }, 429);
        }
        const adminRow = await env.smartvault_db
          .prepare("SELECT email, active, password_salt, password_hash FROM admin_users WHERE email = ? COLLATE NOCASE")
          .bind(adminEmail)
          .first<{ email: string; active: number; password_salt: string | null; password_hash: string | null }>();
        const dummySalt = "00000000000000000000000000000000";
        const dummyHash = "00".repeat(32);
        const adminCheck = await verifyPassword(
          password,
          adminRow?.password_salt ?? dummySalt,
          adminRow?.password_hash ?? dummyHash,
        );
        if (!adminRow || adminRow.active !== 1 || !adminRow.password_salt || !adminRow.password_hash || !adminCheck.valid) {
          await env.smartvault_db
            .prepare(`INSERT INTO admin_login_attempts (key_hash, attempts, window_start) VALUES (?, 1, ?)
               ON CONFLICT(key_hash) DO UPDATE SET
                 attempts = CASE WHEN window_start <= ? THEN 1 ELSE attempts + 1 END,
                 window_start = CASE WHEN window_start <= ? THEN ? ELSE window_start END`)
            .bind(atkKey, now2, now2 - 15 * 60 * 1000, now2 - 15 * 60 * 1000, now2)
            .run();
          return json({ success: false, error: "Invalid credentials" }, 401);
        }
        await env.smartvault_db.prepare("DELETE FROM admin_login_attempts WHERE key_hash = ?").bind(atkKey).run();
        const adminToken = randomToken();
        const adminTokenHash = await sha256Hex(adminToken);
        const adminExpiresAt = now2 + adminSessionLifetimeMs;
        await env.smartvault_db
          .prepare("INSERT INTO admin_sessions (token_hash, admin_email, expires_at, created_at) VALUES (?, ?, ?, ?)")
          .bind(adminTokenHash, adminRow.email, adminExpiresAt, now2)
          .run();
        return json({ success: true, token: adminToken, expires_at: adminExpiresAt, admin: { email: adminRow.email, role: "admin" } });
      }

      if (path === "/api/admin/me" && request.method === "GET") {
        const adm = await authenticatedAdmin(request, env);
        if (!adm) return json({ success: false, error: "Admin authentication required" }, 401);
        return json({ success: true, admin: { email: adm.email, role: "admin" } });
      }

      if (path === "/api/admin/logout" && request.method === "POST") {
        const adm = await authenticatedAdmin(request, env);
        if (!adm) return json({ success: false, error: "Admin authentication required" }, 401);
        await env.smartvault_db
          .prepare("UPDATE admin_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
          .bind(Date.now(), adm.tokenHash)
          .run();
        return json({ success: true });
      }

      if (path === "/api/admin/classification-requests" && request.method === "GET") {
        const adm = await authenticatedAdmin(request, env);
        if (!adm) return json({ success: false, error: "Admin authentication required" }, 401);
        const nowIso = new Date().toISOString();
        await env.smartvault_db
          .prepare("UPDATE classification_requests SET status = 'REJECTED', rejection_reason = 'Request expired' WHERE status = 'PENDING' AND expires_at <= ?")
          .bind(nowIso).run();
        const result = await env.smartvault_db
          .prepare(`SELECT id, user_email, title, message, document_type, status, created_at, expires_at
             FROM classification_requests WHERE status = 'PENDING' AND expires_at > ? ORDER BY created_at ASC`)
          .bind(new Date().toISOString()).all();
        return json({ success: true, requests: result.results });
      }

      if (path === "/api/admin/classification-history" && request.method === "GET") {
        const adm = await authenticatedAdmin(request, env);
        if (!adm) return json({ success: false, error: "Admin authentication required" }, 401);
        const result = await env.smartvault_db
          .prepare("SELECT id, admin_email, request_id, action, details, created_at FROM admin_logs ORDER BY created_at DESC LIMIT 200")
          .all();
        return json({ success: true, history: result.results });
      }


{
  const photoPfx = "/api/admin/classification-requests/";

  if (
    path.startsWith(photoPfx) &&
    path.endsWith("/photo") &&
    request.method === "GET"
  ) {
    const adm = await authenticatedAdmin(request, env);

    if (!adm) {
      return json(
        { success: false, error: "Admin authentication required" },
        401,
      );
    }

    const requestId = path.slice(
      photoPfx.length,
      -"/photo".length,
    );

    if (!requestId || requestId.includes("/")) {
      return json({ success: false, error: "Invalid request ID" }, 400);
    }

    const record = await env.smartvault_db
      .prepare(
        "SELECT image_key, image_mime_type FROM classification_requests WHERE id = ?",
      )
      .bind(requestId)
      .first<{ image_key: string; image_mime_type: string }>();

    if (!record || !record.image_key) {
      return json({ success: false, error: "Classification photo not found" }, 404);
    }

    if (
      !record.image_key.startsWith("/") ||
      (record.image_mime_type !== "image/jpeg" &&
        record.image_mime_type !== "image/png")
    ) {
      return json({ success: false, error: "Invalid stored image information" }, 500);
    }

    try {
      const expiresAt = Math.floor(Date.now() / 1000) + 60;

      const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(env.IMAGEKIT_PRIVATE_KEY),
        { name: "HMAC", hash: "SHA-1" },
        false,
        ["sign"],
      );

      const signatureBuffer = await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(`${record.image_key}${expiresAt}`),
      );

      const signature = Array.from(new Uint8Array(signatureBuffer))
        .map((byte) => byte.toString(16).padStart(2, "0"))
        .join("");

          const endpoint = env.IMAGEKIT_URL_ENDPOINT.replace(/\/+$/, "");

      const imageUrl =
        `${endpoint}${record.image_key}` +
        `?ik-t=${expiresAt}&ik-s=${signature}`;

      const imageResponse = await fetch(imageUrl);

      if (!imageResponse.ok) {
        return json({ success: false, error: "Unable to retrieve image from ImageKit" }, 502);
      }

      return new Response(imageResponse.body, {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": record.image_mime_type,
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
          "Content-Disposition": "inline",
        },
      });
    } catch {
      return json({ success: false, error: "Classification photo retrieval failed" }, 502);
    }
  }
}


      {
        const decPfx = "/api/admin/classification-requests/";
        if (path.startsWith(decPfx) && path.endsWith("/decision") && request.method === "POST") {
          const adm = await authenticatedAdmin(request, env);
          if (!adm) return json({ success: false, error: "Admin authentication required" }, 401);
          let body: unknown;
          try { body = await request.json(); } catch {
            return json({ success: false, error: "Invalid JSON" }, 400);
          }
          if (!isRecord(body)) return json({ success: false, error: "Invalid decision" }, 400);
          const reqId = decodeURIComponent(path.slice(decPfx.length, -"/decision".length));
            const decision = body.decision;
          const level = body.security_level;
          const rawCategory = nullableString(body.category);
          const category = rawCategory === "Pièce d'identité"
            ? "Pièce d’identité"
            : rawCategory;

          const accepted = decision === "accept";
          const optionalMetadata = (value: unknown, maxLength = 200): string | null =>
            typeof value === "string" && value.trim().length > 0
              ? value.trim().slice(0, maxLength)
              : null;
          const firstName = accepted ? optionalMetadata(body.first_name) : null;
          const lastName = accepted ? optionalMetadata(body.last_name) : null;
          const documentNumber = accepted ? optionalMetadata(body.document_number, 80) : null;
          const dateOfBirth = accepted ? optionalMetadata(body.date_of_birth, 10) : null;
          const placeOfBirth = accepted ? optionalMetadata(body.place_of_birth) : null;
          const expirationDate = accepted ? optionalMetadata(body.expiration_date, 10) : null;
          const validDate = (value: string | null) =>
            value === null ||
            (/^\d{4}-\d{2}-\d{2}$/.test(value) &&
              !Number.isNaN(Date.parse(value)));

          if (!validDate(dateOfBirth) || !validDate(expirationDate)) {
            return json({ success: false, error: "Invalid identity date" }, 400);
          }

          const validHigh = [
            "Pièce d’identité",
            "Passeport",
            "Permis de conduire",
            "Autres",
          ];

          const validMedium = [
            "Diplôme",
            "Cours",
            "Notes",
            "Informations",
            "Autres",
          ];

          if (
            (accepted &&
              !(
                (level === "HIGH" && category !== null && validHigh.includes(category)) ||
                (level === "MEDIUM" && category !== null && validMedium.includes(category))
              )) ||
            (!accepted && decision !== "reject")
          ) {
            return json(
              { success: false, error: "Invalid security classification" },
              400,
            );
          }
          const reqRow = await env.smartvault_db
            .prepare("SELECT user_id, title, status FROM classification_requests WHERE id = ?")
            .bind(reqId)
            .first<{ user_id: string; title: string; status: string }>();
          if (!reqRow || reqRow.status !== "PENDING") {
            return json({ success: false, error: "Pending request not found" }, 404);
          }
          const decStatus = accepted ? "ADMIN_REVIEWED" : "REJECTED";
          const rejReason = typeof body.rejection_reason === "string" ? body.rejection_reason.trim().slice(0, 500) : null;
          const upd = await env.smartvault_db
            .prepare(`UPDATE classification_requests SET status = ?, security_level = ?,
               category = ?, rejection_reason = ?, first_name = ?, last_name = ?,
               document_number = ?, date_of_birth = ?, place_of_birth = ?,
               expiration_date = ?, decided_at = CURRENT_TIMESTAMP,
               decided_by = ? WHERE id = ? AND status = 'PENDING'`)
            .bind(
              decStatus,
              accepted ? level : null,
              accepted ? category : null,
              rejReason,
              firstName,
              lastName,
              documentNumber,
              dateOfBirth,
              placeOfBirth,
              expirationDate,
              adm.email,
              reqId,
            )
            .run();
          if (upd.meta.changes !== 1) return json({ success: false, error: "Request was already decided" }, 409);
          await env.smartvault_db
            .prepare("INSERT INTO admin_logs (id, admin_email, request_id, action, details) VALUES (?, ?, ?, ?, ?)")
            .bind(
              crypto.randomUUID(),
              adm.email,
              reqId,
              decStatus,
              accepted
                ? JSON.stringify({
                    level,
                    category,
                    firstName,
                    lastName,
                    documentNumber,
                    dateOfBirth,
                    placeOfBirth,
                    expirationDate,
                  })
                : rejReason,
            )
            .run();
          // Notification utilisateur
          const notifTitle = accepted ? `✅ Document accepté : ${reqRow.title}` : `❌ Document refusé : ${reqRow.title}`;
          const notifBody = accepted
            ? `Votre document a été classifié « ${category} » (niveau ${level === "HIGH" ? "Très sensible" : "Moyennement sensible"}).`
            : `Votre demande a été refusée.${rejReason ? ` Motif : ${rejReason}` : ""}`;
          await env.smartvault_db
            .prepare(`INSERT INTO user_notifications
               (id, user_id, type, title, body, request_id, category, security_level, is_read, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`)
            .bind(crypto.randomUUID(), reqRow.user_id, accepted ? "document_accepted" : "document_rejected",
              notifTitle, notifBody, reqId, accepted ? category : null, accepted ? level : null, Date.now())
            .run();
                      // Envoyer une notification Push au téléphone de l'utilisateur
          try {
            const tokenRows = await env.smartvault_db
              .prepare(
                "SELECT token FROM push_notification_tokens WHERE user_id = ?"
              )
              .bind(reqRow.user_id)
              .all<{ token: string }>();

            for (const row of tokenRows.results ?? []) {
              try {
                await sendFirebasePush(
                  env,
                  row.token,
                  notifTitle,
                  notifBody,
                  {
                    type: accepted
                      ? "document_accepted"
                      : "document_rejected",
                    request_id: reqId,
                  },
                );
              } catch (error) {
                console.error("Push notification failed:", error);
              }
            }
          } catch (error) {
            console.error("Push notification dispatch failed:", error);
          }
          return json({
            success: true,
            status: decStatus,
            security_level: accepted ? level : null,
            category: accepted ? category : null,
            first_name: firstName,
            last_name: lastName,
            document_number: documentNumber,
            date_of_birth: dateOfBirth,
            place_of_birth: placeOfBirth,
            expiration_date: expirationDate,
          });
        }
      }

      // ── Fin des routes admin indépendantes ───────────────────────────────

      const principal = await authenticatedPrincipal(request, env);
      if (!principal) {
        return json({ success: false, error: "Authentication required" }, 401);
      }
      const { uid: userId, email } = principal;
if (path === "/api/push/register" && request.method === "POST") {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return json({ success: false, error: "Invalid JSON" }, 400);
  }

  if (!isRecord(body)) {
    return json({ success: false, error: "Invalid token data" }, 400);
  }

  const token = nullableString(body.token);
  const platform = body.platform;

  if (
    !token ||
    token.length > 4096 ||
    (platform !== "android" && platform !== "ios")
  ) {
    return json({ success: false, error: "Invalid FCM token" }, 400);
  }

  const now = Date.now();

  await env.smartvault_db
    .prepare(`
      INSERT INTO push_notification_tokens
        (id, user_id, token, platform, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(token) DO UPDATE SET
        user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = excluded.updated_at
    `)
    .bind(
      crypto.randomUUID(),
      userId,
      token,
      platform,
      now,
      now,
    )
    .run();

  return json({ success: true, message: "FCM token registered" });
}
      // ── User notifications ─────────────────────────────────────────

      if (path === "/api/notifications" && request.method === "GET") {
        const result = await env.smartvault_db
          .prepare(
            `SELECT id, type, title, body, request_id, category,
                    security_level, is_read, created_at
             FROM user_notifications
             WHERE user_id = ?
             ORDER BY created_at DESC
             LIMIT 100`,
          )
          .bind(userId)
          .all<{
            id: string;
            type: string;
            title: string;
            body: string;
            request_id: string;
            category: string | null;
            security_level: string | null;
            is_read: number;
            created_at: number;
          }>();

        const unread = await env.smartvault_db
          .prepare(
            `SELECT COUNT(*) AS total
             FROM user_notifications
             WHERE user_id = ? AND is_read = 0`,
          )
          .bind(userId)
          .first<{ total: number }>();

        return json({
          success: true,
          notifications: result.results.map((row) => ({
            ...row,
            is_read: Number(row.is_read) === 1,
          })),
          unread_count: Number(unread?.total ?? 0),
        });
      }

      if (
        path === "/api/notifications/read-all" &&
        request.method === "POST"
      ) {
        await env.smartvault_db
          .prepare(
            `UPDATE user_notifications
             SET is_read = 1
             WHERE user_id = ? AND is_read = 0`,
          )
          .bind(userId)
          .run();

        return json({ success: true });
      }

      // ── End user notifications ─────────────────────────────────────

      if (path === "/api/session" && request.method === "GET") {
        return json({
          success: true,
          user: {
            id: userId,
            email,
            display_name: principal.displayName,
          },
          isAdmin: await isAdministrator(principal, env),
        });
      }

      if (
        (path === "/api/auth/session" && request.method === "DELETE") ||
        (path === "/api/auth/logout" && request.method === "POST")
      ) {
        await env.smartvault_db
          .prepare("UPDATE auth_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL")
          .bind(Date.now(), principal.tokenHash)
          .run();
        return json({ success: true });
      }

      if (path === "/api/auth/reauthenticate" && request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body) || typeof body.password !== "string" || body.password.length > 128) {
          return json({ success: false, error: "Invalid credentials" }, 400);
        }
        const user = await env.smartvault_db
          .prepare("SELECT password_salt, password_hash FROM auth_users WHERE id = ?")
          .bind(userId)
          .first<{ password_salt: string; password_hash: string }>();
        const check = await verifyPassword(body.password, user?.password_salt ?? "", user?.password_hash ?? "");
        if (
          !user ||
          !check.valid
        ) {
          return json({ success: false, error: "Invalid email or password" }, 401);
        }
        if (check.needsRehash) {
          const newSaltBytes = crypto.getRandomValues(new Uint8Array(16));
          const newSalt = toHex(newSaltBytes);
          const newHash = await hashPassword(body.password, newSalt, DEFAULT_PASSWORD_ITERATIONS);
          await env.smartvault_db
            .prepare("UPDATE auth_users SET password_salt = ?, password_hash = ? WHERE id = ?")
            .bind(newSalt, newHash, userId)
            .run();
        }
        return json({ success: true });
      }

      if (path === "/api/shares" && request.method === "POST") {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body)) {
          return json({ success: false, error: "Invalid share request" }, 400);
        }
        const documentId = nullableString(body.document_id);
        const duration = body.duration_minutes;
        const fields = body.fields;
        const frontImage = validImage({
          image_base64: body.front_image_base64,
          image_mime_type: body.front_image_mime_type,
        });
        const backImage = body.back_image_base64 == null && body.back_image_mime_type == null
          ? null
          : validImage({
              image_base64: body.back_image_base64,
              image_mime_type: body.back_image_mime_type,
            });
        const allowedFields = new Set([
          "category",
          "holderName",
          "firstName",
          "lastName",
          "documentNumber",
          "dateOfBirth",
          "placeOfBirth",
          "expirationDate",
        ]);
        if (
          !documentId ||
          documentId.length > 80 ||
          !frontImage ||
          ((body.back_image_base64 == null) !== (body.back_image_mime_type == null)) ||
          (body.back_image_base64 != null && !backImage) ||
          typeof duration !== "number" ||
          ![5, 15, 30, 60, 1440].includes(duration) ||
          !isRecord(fields) ||
          Object.keys(fields).length === 0 ||
          Object.keys(fields).length > allowedFields.size ||
          Object.entries(fields).some(
            ([key, value]) =>
              !allowedFields.has(key) ||
              typeof value !== "string" ||
              value.trim().length === 0 ||
              value.length > 300,
          )
        ) {
          return json({ success: false, error: "Invalid share request" }, 400);
        }

        const doc = await env.smartvault_db
          .prepare("SELECT id FROM documents WHERE id = ? AND user_id = ?")
          .bind(documentId, userId)
          .first();
        if (!doc) {
          return json({ success: false, error: "Document not found" }, 404);
        }

        const id = crypto.randomUUID();
        const token = randomToken();
        const now = Date.now();
        const expiresAt = now + duration * 60 * 1000;
        let imagesJson: string;
        try {
          const frontPath = await uploadClassificationImage(env, frontImage!, "/smartvault-shares", "share-front");
          const images: Record<string, { path: string; mime: string }> = {
            front: { path: frontPath, mime: frontImage!.mimeType },
          };
          if (backImage) {
            const backPath = await uploadClassificationImage(env, backImage, "/smartvault-shares", "share-back");
            images.back = { path: backPath, mime: backImage.mimeType };
          }
          imagesJson = JSON.stringify(images);
        } catch (error) {
          console.error("Share image upload failed:", error);
          return json({ success: false, error: "Unable to upload document photos" }, 502);
        }
        await env.smartvault_db
          .prepare(
            `INSERT INTO document_shares
             (id, user_id, document_id, token_hash, fields_json, images_json, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(
            id,
            userId,
            documentId,
            await sha256Hex(token),
            JSON.stringify(
              Object.fromEntries(
                Object.entries(fields).map(([key, value]) => [
                  key,
                  (value as string).trim(),
                ]),
              ),
            ),
            imagesJson,
            expiresAt,
            now,
          )
          .run();
        return json(
          {
            success: true,
            share: {
              id,
              url: `${url.origin}/share#${token}`,
              expires_at: expiresAt,
              created_at: now,
              status: "active",
            },
          },
          201,
        );
      }

      if (path === "/api/shares" && request.method === "GET") {
        const documentId = url.searchParams.get("document_id");
        if (!documentId || documentId.length > 80) {
          return json({ success: false, error: "Document ID is required" }, 400);
        }
        const rows = await env.smartvault_db
          .prepare(
            `SELECT id, expires_at, created_at, revoked_at
             FROM document_shares WHERE user_id = ? AND document_id = ?
             ORDER BY created_at DESC`,
          )
          .bind(userId, documentId)
          .all<{
            id: string;
            expires_at: number;
            created_at: number;
            revoked_at: number | null;
          }>();
        return json({
          success: true,
          shares: rows.results.map((share) => ({
            id: share.id,
            expires_at: share.expires_at,
            created_at: share.created_at,
            status: share.revoked_at
              ? "revoked"
              : share.expires_at <= Date.now()
                ? "expired"
                : "active",
          })),
        });
      }

      const revokePrefix = "/api/shares/";
      if (
        path.startsWith(revokePrefix) &&
        request.method === "DELETE"
      ) {
        const id = decodeURIComponent(path.slice(revokePrefix.length));
        const result = await env.smartvault_db
          .prepare(
            `UPDATE document_shares SET revoked_at = ?
             WHERE id = ? AND user_id = ? AND revoked_at IS NULL`,
          )
          .bind(Date.now(), id, userId)
          .run();
        if (result.meta.changes !== 1) {
          return json({ success: false, error: "Share not found" }, 404);
        }
        return json({ success: true });
      }


if (path === "/api/classification-requests" && request.method === "POST") {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ success: false, error: "Invalid JSON" }, 400);
  }

  if (!isRecord(body)) {
    return json({ success: false, error: "Invalid request" }, 400);
  }

  const id = nullableString(body.id);
  const title = nullableString(body.title);
  const documentType = nullableString(body.document_type);
  const message =
    typeof body.message === "string" ? body.message.trim().slice(0, 500) : "";

  if (!id || id.length > 80 || !title || title.length > 120 || !documentType) {
    return json({ success: false, error: "Invalid classification request" }, 400);
  }

  const image = validImage(body);
  if (!image) {
    return json({ success: false, error: "Invalid or missing image" }, 400);
  }

  const existing = await env.smartvault_db
    .prepare(
      "SELECT user_id, status, image_key FROM classification_requests WHERE id = ?",
    )
    .bind(id)
    .first<{ user_id: string; status: string; image_key: string }>();

  if (existing && existing.user_id !== userId) {
    return json({ success: false, error: "Request already exists" }, 409);
  }

  if (existing && existing.image_key) {
    return json({ success: true, status: existing.status });
  }

  const extension = image.mimeType === "image/png" ? "png" : "jpg";
  const fileName = `classification-${id}.${extension}`;

  const uploadForm = new FormData();
  uploadForm.append(
    "file",
    new Blob([image.bytes], { type: image.mimeType }),
    fileName,
  );
  uploadForm.append("fileName", fileName);
  uploadForm.append("folder", "/smartvault/classification-requests");
  uploadForm.append("useUniqueFileName", "true");
  uploadForm.append("isPrivateFile", "true");

  let uploadResponse: Response;
  try {
    uploadResponse = await fetch(
      "https://upload.imagekit.io/api/v1/files/upload",
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${env.IMAGEKIT_PRIVATE_KEY}:`)}`,
        },
        body: uploadForm,
      },
    );
  } catch {
    return json({ success: false, error: "Image upload failed" }, 502);
  }

  if (!uploadResponse.ok) {
    return json({ success: false, error: "ImageKit upload failed" }, 502);
  }

  let uploadResult: unknown;
  try {
    uploadResult = await uploadResponse.json();
  } catch {
    return json({ success: false, error: "Invalid ImageKit response" }, 502);
  }

  if (
    !isRecord(uploadResult) ||
    typeof uploadResult.filePath !== "string" ||
    !uploadResult.filePath.startsWith("/")
  ) {
    return json({ success: false, error: "ImageKit did not return a valid file path" }, 502);
  }

  const imageKey = uploadResult.filePath;
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  if (existing) {
    await env.smartvault_db
      .prepare(
        `UPDATE classification_requests
         SET image_key = ?, image_mime_type = ?
         WHERE id = ? AND user_id = ?`,
      )
      .bind(imageKey, image.mimeType, id, userId)
      .run();

    return json({ success: true, status: existing.status });
  }

  await env.smartvault_db
    .prepare(
      `INSERT INTO classification_requests
       (id, user_id, user_email, title, message, document_type,
        image_key, image_mime_type, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      id,
      userId,
      email,
      title,
      message,
      documentType,
      imageKey,
      image.mimeType,
      expiresAt,
    )
    .run();

  return json(
    { success: true, status: "PENDING", expires_at: expiresAt },
    201,
  );
}

      if (path === "/api/classification-requests/mine" && request.method === "GET") {
        const result = await env.smartvault_db
          .prepare(
            `SELECT id, title, document_type, status, security_level, category,
                    rejection_reason, first_name, last_name, document_number,
                    date_of_birth, place_of_birth, expiration_date,
                    created_at, expires_at
             FROM classification_requests WHERE user_id = ? ORDER BY created_at DESC`,
          )
          .bind(userId)
          .all();
        return json({ success: true, requests: result.results });
      }
      // (routes admin traitees avant authenticatedPrincipal)
      // GET: List all documents
      if (path === "/api/documents" && request.method === "GET") {
        const result = await env.smartvault_db
          .prepare(
            "SELECT * FROM documents WHERE user_id = ? ORDER BY created_at DESC",
          )
          .bind(userId)
          .all();

        return json({
          success: true,
          documents: result.results.map((row) => documentFromRow(row)),
        });
      }

      // POST: Add a document
      if (path === "/api/documents" && request.method === "POST") {
        let body: unknown;

        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }

        if (!isRecord(body)) {
          return json({ success: false, error: "Invalid document" }, 400);
        }
        const title = nullableString(body.title);
        const category = nullableString(body.category);
        const imageStoragePath = nullableString(body.image_storage_path);
        if (!title || !category) {
          return json({
            success: false,
            error: "Title and category are required",
          }, 400);
        }

        if (
          imageStoragePath &&
          !imageStoragePath.startsWith(`users/${userId}/documents/`)
        ) {
          return json({ success: false, error: "Invalid image path" }, 400);
        }

        const id = nullableString(body.id) ?? crypto.randomUUID();
        const fileName =
          nullableString(body.file_name) ??
          imageStoragePath?.split("/").pop() ??
          null;
        await env.smartvault_db
          .prepare(
            `INSERT INTO documents (
               id, user_id, title, category, file_name, holder_name,
               document_number, expiry_date, name, surname, date_of_birth,
               place_of_birth, image_storage_path, document_type, full_name,
               first_name, last_name, cin_number, expiration_date, updated_at
             ) VALUES (
               ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
               CURRENT_TIMESTAMP
             )`,
          )
          .bind(
            id,
            userId,
            title,
            category,
            fileName,
            nullableString(body.holder_name),
            nullableString(body.document_number),
            nullableString(body.expiry_date),
            nullableString(body.name),
            nullableString(body.surname),
            nullableString(body.date_of_birth),
            nullableString(body.place_of_birth),
            imageStoragePath,
            nullableString(body.document_type),
            nullableString(body.full_name),
            nullableString(body.first_name),
            nullableString(body.last_name),
            nullableString(body.cin_number),
            nullableString(body.expiration_date),
          )
          .run();

        const savedDocument = await env.smartvault_db
          .prepare("SELECT * FROM documents WHERE id = ? AND user_id = ?")
          .bind(id, userId)
          .first();
        if (!savedDocument) {
          throw new Error("Document insert could not be read back");
        }

        return json({
          success: true,
          message: "Document saved successfully",
          document: documentFromRow(savedDocument),
        }, 201);
      }

      // GET: Find one document by ID
      if (

        path.startsWith("/api/documents/") &&
        request.method === "GET"
      ) {
        const id = decodeURIComponent(path.slice("/api/documents/".length));

        const document = await env.smartvault_db
          .prepare("SELECT * FROM documents WHERE id = ? AND user_id = ?")
          .bind(id, userId)
          .first();

        if (!document) {
          return json({
            success: false,
            error: "Document not found",
          }, 404);
        }

        return json({
          success: true,
          document: documentFromRow(document),
        });
      }

      // DELETE: Delete one document by ID
      if (
        path.startsWith("/api/documents/") &&
        request.method === "DELETE"
      ) {
        const id = decodeURIComponent(path.slice("/api/documents/".length));

        const result = await env.smartvault_db
          .prepare("DELETE FROM documents WHERE id = ? AND user_id = ?")
          .bind(id, userId)
          .run();

        if (result.meta.changes === 0) {
          return json({
            success: false,
            error: "Document not found",
          }, 404);
        }

        return json({
          success: true,
          message: "Document deleted successfully",
        });
      }

      return json({
        success: false,
        error: "Route not found",
      }, 404);

    } catch (error) {
      console.error("API error:", error);

      return json({
        success: false,
        error: "Internal server error",
      }, 500);
    }
  },
  async scheduled(_controller, env): Promise<void> {
    await env.smartvault_db
      .prepare("UPDATE classification_requests SET status = 'REJECTED', rejection_reason = 'Request expired' WHERE status = 'PENDING' AND expires_at <= ?")
      .bind(new Date().toISOString())
      .run();
    const now = Date.now();
    await env.smartvault_db
      .prepare("DELETE FROM auth_sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL")
      .bind(now)
      .run();
    await env.smartvault_db
      .prepare("DELETE FROM auth_login_attempts WHERE window_start <= ?")
      .bind(now - 24 * 60 * 60 * 1000)
      .run();
  },
} satisfies ExportedHandler<Env>;
