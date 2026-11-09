
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

const passwordIterations = 310_000;
const sessionLifetimeMs = 30 * 24 * 60 * 60 * 1000;

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

export async function hashPassword(
  password: string,
  salt: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt: fromHex(salt),
      iterations: passwordIterations,
    },
    key,
    256,
  );
  return toHex(new Uint8Array(bits));
}

async function verifyPassword(
  password: string,
  salt: string,
  expectedHash: string,
): Promise<boolean> {
  let actual: Uint8Array;
  let expected: Uint8Array;
  try {
    actual = fromHex(await hashPassword(password, salt));
    expected = fromHex(expectedHash);
  } catch {
    return false;
  }
  if (actual.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual[index] ^ expected[index];
  }
  return difference === 0;
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

async function expirePendingClassificationRequests(env: Env): Promise<void> {
  await env.smartvault_db
    .prepare(
      `UPDATE classification_requests
       SET status = 'REJECTED',
           rejection_reason = 'Request expired',
           decided_at = CURRENT_TIMESTAMP
       WHERE status = 'PENDING' AND expires_at <= ?`,
    )
    .bind(new Date().toISOString())
    .run();
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

        const token = randomToken();
        const tokenHash = await sha256Hex(token);
        const expiresAt = now + sessionLifetimeMs;

        try {
          await env.smartvault_db.batch([
            env.smartvault_db
              .prepare(
                `INSERT INTO auth_users (id, email, display_name, password_salt, password_hash, created_at)
                 VALUES (?, ?, ?, ?, ?, ?)`,
              )
              .bind(userId, email, displayName, salt, hashedPassword, now),
            env.smartvault_db
              .prepare(
                "INSERT INTO auth_sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
              )
              .bind(tokenHash, userId, expiresAt, now),
          ]);
        } catch (err: unknown) {
          const message = err instanceof Error ? err.message : String(err);
          if (message.includes("UNIQUE") || message.includes("constraint")) {
            return json({ success: false, error: "Email already in use" }, 409);
          }
          throw err;
        }

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
        const valid = await verifyPassword(
          password,
          user?.password_salt ?? "00000000000000000000000000000000",
          user?.password_hash ?? "00".repeat(32),
        );
        if (!user || !valid) {
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
            `SELECT fields_json FROM document_shares
             WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
          )
          .bind(await sha256Hex(body.token), Date.now())
          .first<{ fields_json: string }>();
        if (!row) {
          return json({ success: false, error: "Share link is expired or revoked" }, 404);
        }
        return json({ success: true, fields: JSON.parse(row.fields_json) });
      }

      if (path === "/share" && request.method === "GET") {
        return new Response(
          `<!doctype html>
<html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Document partagé · SmartVault Pro</title>
<style>body{font:16px system-ui,sans-serif;max-width:640px;margin:12vh auto;padding:24px;color:#172b3a;background:#f4f7f7}main{background:white;padding:24px;border-radius:16px}dt{font-weight:700;margin-top:14px}dd{margin:4px 0;color:#526870}</style>
<main><h1>Informations partagées</h1><p id="status">Vérification du lien…</p><dl id="fields"></dl></main>
<script>
const status = document.getElementById('status');
const fields = document.getElementById('fields');
const labels = {category:'Catégorie',holderName:'Titulaire',firstName:'Prénom',lastName:'Nom',documentNumber:'Numéro du document',dateOfBirth:'Date de naissance',placeOfBirth:'Lieu de naissance',expirationDate:'Date d’expiration'};
const token = location.hash.slice(1);
history.replaceState(null, '', location.pathname);
fetch('/api/shares/open', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})})
  .then(async response => {
    const data = await response.json();
    if (!response.ok || !data.success || typeof data.fields !== 'object') throw new Error();
    status.textContent = 'Ce lien est temporaire. La photo du document n’est pas partagée.';
    for (const [key, value] of Object.entries(data.fields)) {
      if (typeof value !== 'string' || !labels[key]) continue;
      const label = document.createElement('dt');
      label.textContent = labels[key];
      const item = document.createElement('dd');
      item.textContent = value;
      fields.append(label, item);
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
                "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
              "Referrer-Policy": "no-referrer",
              "X-Content-Type-Options": "nosniff",
            },
          },
        );
      }

      const principal = await authenticatedPrincipal(request, env);
      if (!principal) {
        return json({ success: false, error: "Authentication required" }, 401);
      }
      const { uid: userId, email } = principal;

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
        if (
          !user ||
          !(await verifyPassword(body.password, user.password_salt, user.password_hash))
        ) {
          return json({ success: false, error: "Invalid email or password" }, 401);
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

        const ownedDocument = await env.smartvault_db
          .prepare("SELECT 1 FROM documents WHERE id = ? AND user_id = ?")
          .bind(documentId, userId)
          .first();
        if (!ownedDocument) {
          return json({ success: false, error: "Document not found" }, 404);
        }

        const id = crypto.randomUUID();
        const token = randomToken();
        const now = Date.now();
        const expiresAt = now + duration * 60 * 1000;
        await env.smartvault_db
          .prepare(
            `INSERT INTO document_shares
             (id, user_id, document_id, token_hash, fields_json, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
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
        const existing = await env.smartvault_db
          .prepare("SELECT user_id, status FROM classification_requests WHERE id = ?")
          .bind(id)
          .first<{ user_id: string; status: string }>();
        if (existing) {
          if (existing.user_id !== userId) {
            return json({ success: false, error: "Request already exists" }, 409);
          }
          return json({ success: true, status: existing.status });
        }

        const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
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
            "",
            "",
            expiresAt,
          )
          .run();

        return json(
          { success: true, status: "PENDING", expires_at: expiresAt },
          201,
        );
      }

      if (path === "/api/classification-requests/mine" && request.method === "GET") {
        await expirePendingClassificationRequests(env);
        const result = await env.smartvault_db
          .prepare(
            `SELECT id, title, document_type, status, security_level, category,
                    rejection_reason, created_at, expires_at
             FROM classification_requests WHERE user_id = ? ORDER BY created_at DESC`,
          )
          .bind(userId)
          .all();
        return json({ success: true, requests: result.results });
      }

      const adminPath = path.startsWith("/api/admin/");
      if (adminPath && !(await isAdministrator(principal, env))) {
        return json({ success: false, error: "Administrator access required" }, 403);
      }

      if (
        path === "/api/admin/classification-requests" &&
        request.method === "GET"
      ) {
        await expirePendingClassificationRequests(env);
        const result = await env.smartvault_db
          .prepare(
            `SELECT id, user_email, title, message, document_type, status,
                    created_at, expires_at
             FROM classification_requests
             WHERE status = 'PENDING' ORDER BY created_at ASC`,
          )
          .all();
        return json({ success: true, requests: result.results });
      }

      if (
        path === "/api/admin/classification-history" &&
        request.method === "GET"
      ) {
        const result = await env.smartvault_db
          .prepare(
            `SELECT id, admin_email, request_id, action, details, created_at
             FROM admin_logs ORDER BY created_at DESC LIMIT 200`,
          )
          .all();
        return json({ success: true, history: result.results });
      }

      const photoPrefix = "/api/admin/classification-requests/";

      if (
        path.startsWith(photoPrefix) &&
        path.endsWith("/photo") &&
        request.method === "GET"
      ) {
        return json(
          {
            success: false,
            error: "Classification photo storage is not available.",
          },
          503,
        );
      }

      const decisionPrefix = "/api/admin/classification-requests/";
      if (
        path.startsWith(decisionPrefix) &&
        path.endsWith("/decision") &&
        request.method === "POST"
      ) {
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json({ success: false, error: "Invalid JSON" }, 400);
        }
        if (!isRecord(body)) return json({ success: false, error: "Invalid decision" }, 400);
        const id = decodeURIComponent(path.slice(decisionPrefix.length, -"/decision".length));
        const decision = body.decision;
        const level = body.security_level;
        const category = nullableString(body.category);
        const accepted = decision === "accept";
        const validHigh = ["Pièce d’identité", "Passeport", "Permis de conduire", "Autres"];
        const validMedium = ["Diplôme", "Cours", "Notes", "Informations", "Autres"];
        if (
          (accepted && !((level === "HIGH" && category && validHigh.includes(category)) ||
            (level === "MEDIUM" && category && validMedium.includes(category)))) ||
          (!accepted && decision !== "reject")
        ) {
          return json({ success: false, error: "Invalid security classification" }, 400);
        }
        const row = await env.smartvault_db
          .prepare("SELECT status FROM classification_requests WHERE id = ?")
          .bind(id)
          .first<{ status: string }>();
        if (!row || row.status !== "PENDING") {
          return json({ success: false, error: "Pending request not found" }, 404);
        }
        const status = accepted ? "ADMIN_REVIEWED" : "REJECTED";
        const rejectionReason =
          typeof body.rejection_reason === "string"
            ? body.rejection_reason.trim().slice(0, 500)
            : null;
        const decisionDetails = accepted
          ? JSON.stringify({ level, category })
          : rejectionReason;
        const [updateResult] = await env.smartvault_db.batch([
          env.smartvault_db
            .prepare(
              `UPDATE classification_requests SET status = ?, security_level = ?,
                 category = ?, rejection_reason = ?, decided_at = CURRENT_TIMESTAMP,
                 decided_by = ? WHERE id = ? AND status = 'PENDING'`,
            )
            .bind(
              status,
              accepted ? level : null,
              accepted ? category : null,
              rejectionReason,
              email,
              id,
            ),
          env.smartvault_db
            .prepare(
              `INSERT INTO admin_logs
                 (id, admin_email, request_id, action, details)
               SELECT ?, ?, ?, ?, ? WHERE changes() = 1`,
            )
            .bind(crypto.randomUUID(), email, id, status, decisionDetails),
        ]);
        if (updateResult.meta.changes !== 1) {
          return json({ success: false, error: "Request was already decided" }, 409);
        }

        return json({ success: true, status, security_level: accepted ? level : null, category: accepted ? category : null });
      }

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
    await expirePendingClassificationRequests(env);
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
