import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
	SELF,
} from "cloudflare:test";
import { beforeAll, describe, it, expect, vi } from "vitest";
import worker, { hashPassword } from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

async function createAccount(email: string, isAdmin = false) {
	const id = crypto.randomUUID();
	const salt = crypto.randomUUID().replaceAll("-", "");
	const password = "test-password-123";
	await env.smartvault_db
		.prepare(
			"INSERT INTO auth_users (id, email, display_name, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
		)
		.bind(
			id,
			email,
			"Test User",
			salt,
			await hashPassword(password, salt),
			Date.now(),
		)
		.run();
	if (isAdmin) {
		await env.smartvault_db
			.prepare("INSERT INTO admin_users (email, active, user_id) VALUES (?, 1, ?)")
			.bind(email, id)
			.run();
	}
	return { id, email, password };
}

async function login(email: string, password: string) {
	return SELF.fetch("https://example.com/api/auth/login", {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({ email, password }),
	});
}

function authorizationHeader(token: string): string {
	return ["Bearer", token].join(" ");
}

beforeAll(async () => {
	const schema = [
		`CREATE TABLE auth_users (
			id TEXT PRIMARY KEY NOT NULL,
			email TEXT NOT NULL UNIQUE COLLATE NOCASE,
			display_name TEXT NOT NULL,
			password_salt TEXT NOT NULL,
			password_hash TEXT NOT NULL,
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE auth_sessions (
			token_hash TEXT PRIMARY KEY NOT NULL,
			user_id TEXT NOT NULL,
			expires_at INTEGER NOT NULL,
			created_at INTEGER NOT NULL,
			revoked_at INTEGER
		)`,
		`CREATE TABLE auth_login_attempts (
			key_hash TEXT PRIMARY KEY NOT NULL,
			attempts INTEGER NOT NULL,
			window_start INTEGER NOT NULL
		)`,
		`CREATE TABLE admin_users (
			email TEXT PRIMARY KEY NOT NULL,
			active INTEGER NOT NULL DEFAULT 1,
			user_id TEXT
		)`,
		`CREATE TABLE classification_requests (
			id TEXT PRIMARY KEY NOT NULL,
			user_id TEXT NOT NULL,
			user_email TEXT NOT NULL,
			title TEXT NOT NULL,
			message TEXT,
			document_type TEXT NOT NULL,
			image_key TEXT NOT NULL,
			image_mime_type TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'PENDING',
			security_level TEXT,
			category TEXT,
			rejection_reason TEXT,
			created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
			expires_at TEXT NOT NULL,
			decided_at TEXT,
			decided_by TEXT
		)`,
		`CREATE TABLE document_shares (
			id TEXT PRIMARY KEY NOT NULL,
			user_id TEXT NOT NULL,
			document_id TEXT NOT NULL,
			token_hash TEXT NOT NULL UNIQUE,
			fields_json TEXT NOT NULL,
			images_json TEXT,
			expires_at INTEGER NOT NULL,
			created_at INTEGER NOT NULL,
			revoked_at INTEGER
		)`,
		`CREATE TABLE documents (
			id TEXT PRIMARY KEY NOT NULL,
			user_id TEXT,
			title TEXT NOT NULL,
			category TEXT NOT NULL,
			file_name TEXT,
			created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
			holder_name TEXT,
			document_number TEXT,
			expiry_date TEXT,
			name TEXT,
			surname TEXT,
			date_of_birth TEXT,
			place_of_birth TEXT,
			image_storage_path TEXT,
			document_type TEXT,
			full_name TEXT,
			first_name TEXT,
			last_name TEXT,
			cin_number TEXT,
			expiration_date TEXT,
			updated_at TEXT,
			status TEXT,
			security_level TEXT NOT NULL DEFAULT 'PENDING',
			classification_status TEXT NOT NULL DEFAULT 'PENDING',
			classification_source TEXT NOT NULL DEFAULT 'AUTOMATIC'
		)`,
		`CREATE TABLE admin_logs (
			id TEXT PRIMARY KEY NOT NULL,
			admin_email TEXT NOT NULL,
			request_id TEXT NOT NULL,
			action TEXT NOT NULL,
			details TEXT,
			created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
	];
	for (const statement of schema) {
		await env.smartvault_db.prepare(statement).run();
	}
});

describe("SmartVault Worker", () => {
	it("reports that the API is running", async () => {
		const request = new IncomingRequest("http://example.com/");
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			success: true,
			message: "SmartVault Pro API is running",
		});
	});

	it("requires an active Cloudflare session to access private routes", async () => {
		const response = await SELF.fetch("https://example.com/api/documents");
		expect(response.status).toBe(401);
		expect(await response.json()).toEqual({
			success: false,
			error: "Authentication required",
		});
	});

	it("rejects malformed bearer tokens", async () => {
		const response = await SELF.fetch("https://example.com/api/documents", {
			headers: { Authorization: "not-a-session-token" },
		});
		expect(response.status).toBe(401);
	});

	it("keeps password reset unavailable without email delivery", async () => {
		const reset = await SELF.fetch("https://example.com/api/auth/password-reset", {
			method: "POST",
		});
		expect(reset.status).toBe(503);
	});

	it("successfully registers a new user and activates the account immediately", async () => {
		const payload = {
			name: "Jane Doe",
			email: "jane.doe@example.com",
			password: "SecurePassword123!",
		};
		const response = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(payload),
		});

		expect(response.status).toBe(201);
		const body = await response.json() as {
			success: boolean;
			token: string;
			expires_at: number;
			user: { id: string; email: string; display_name: string };
			isAdmin: boolean;
		};

		expect(body.success).toBe(true);
		expect(typeof body.token).toBe("string");
		expect(body.token.length).toBeGreaterThan(20);
		expect(body.user.email).toBe("jane.doe@example.com");
		expect(body.user.display_name).toBe("Jane Doe");
		expect(body.isAdmin).toBe(false);
		expect(body.expires_at).toBeGreaterThan(Date.now());

		// Verify stored permanently in auth_users
		const storedUser = await env.smartvault_db
			.prepare("SELECT * FROM auth_users WHERE email = ?")
			.bind(body.user.email)
			.first<{
				id: string;
				email: string;
				display_name: string;
				password_salt: string;
				password_hash: string;
			}>();
		expect(storedUser).toBeDefined();
		expect(storedUser?.id).toBe(body.user.id);
		expect(storedUser?.display_name).toBe("Jane Doe");
		expect(storedUser?.password_hash).not.toBe(payload.password);
		expect(storedUser?.password_salt).toBeDefined();

		// Verify session stored in auth_sessions as sha256 hash
		const storedSession = await env.smartvault_db
			.prepare("SELECT * FROM auth_sessions WHERE user_id = ?")
			.bind(body.user.id)
			.first<{ token_hash: string; expires_at: number }>();
		expect(storedSession).toBeDefined();
		expect(storedSession?.token_hash).not.toBe(body.token);

		// Can immediately access authenticated endpoint with returned token
		const sessionResponse = await SELF.fetch("https://example.com/api/session", {
			headers: { Authorization: `Bearer ${body.token}` },
		});
		expect(sessionResponse.status).toBe(200);
		const sessionData = await sessionResponse.json() as { user: { id: string }; isAdmin: boolean };
		expect(sessionData.user.id).toBe(body.user.id);
		expect(sessionData.isAdmin).toBe(false);

		// Can log in directly with the newly created credentials
		const loginResponse = await login(payload.email, payload.password);
		expect(loginResponse.status).toBe(200);
		const loginData = await loginResponse.json() as { user: { id: string }; isAdmin: boolean };
		expect(loginData.user.id).toBe(body.user.id);
		expect(loginData.isAdmin).toBe(false);
	});

	it("rejects duplicate email registration case-insensitively", async () => {
		const payload = {
			name: "Duplicate Tester",
			email: "duplicate@example.com",
			password: "SecurePassword123!",
		};
		const first = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(payload),
		});

		expect(first.status).toBe(201);

		// Same email with different case
		const second = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				name: "Duplicate Tester 2",
				email: "DUPLICATE@EXAMPLE.COM",
				password: "SecurePassword123!",
			}),
		});
		expect(second.status).toBe(409);
		const errorBody = await second.json() as { success: boolean; error: string };
		expect(errorBody.success).toBe(false);
		expect(errorBody.error).toBe("Email already in use");
	});

	it("does not allow normal registration for a provisioned Admin email", async () => {
		await env.smartvault_db
			.prepare("INSERT INTO admin_users (email, active) VALUES (?, 1)")
			.bind("protected-admin@example.com")
			.run();

		const response = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				name: "Protected Admin",
				email: "protected-admin@example.com",
				password: "SecurePassword123!",
			}),
		});

		expect(response.status).toBe(409);
		expect(
			await env.smartvault_db
				.prepare("SELECT 1 FROM auth_users WHERE email = ?")
				.bind("protected-admin@example.com")
				.first(),
		).toBeNull();
	});

	it("validates registration input fields strictly", async () => {
		// Invalid JSON
		const badJson = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: "not json",
		});
		expect(badJson.status).toBe(400);

		// Invalid email
		const badEmail = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				name: "Valid Name",
				email: "invalid-email-format",
				password: "ValidPassword123!",
			}),
		});
		expect(badEmail.status).toBe(400);

		// Short password (< 8 chars)
		const shortPass = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				name: "Valid Name",
				email: "valid@example.com",
				password: "short",
			}),
		});
		expect(shortPass.status).toBe(400);

		// Invalid name (< 2 chars)
		const shortName = await SELF.fetch("https://example.com/api/auth/register", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				name: " ",
				email: "valid2@example.com",
				password: "ValidPassword123!",
			}),
		});
		expect(shortName.status).toBe(400);
	});

	it("authenticates provisioned users and revokes sessions on sign out", async () => {
		const user = await createAccount("user@example.com");
		const loginResponse = await login(user.email, user.password);
		expect(loginResponse.status).toBe(200);
		const loginBody = await loginResponse.json() as {
			token: string;
			user: { id: string; email: string; display_name: string };
			isAdmin: boolean;
		};
		expect(loginBody.user).toEqual({
			id: user.id,
			email: user.email,
			display_name: "Test User",
		});
		expect(loginBody.isAdmin).toBe(false);

		const storedSession = await env.smartvault_db
			.prepare("SELECT token_hash FROM auth_sessions WHERE user_id = ?")
			.bind(user.id)
			.first<{ token_hash: string }>();
		expect(storedSession?.token_hash).not.toBe(loginBody.token);

		const headers = { Authorization: `Bearer ${loginBody.token}` };
		const session = await SELF.fetch("https://example.com/api/session", { headers });
		expect(session.status).toBe(200);
		expect((await session.json() as { user: { id: string } }).user.id).toBe(user.id);

		const signedOut = await SELF.fetch("https://example.com/api/auth/session", {
			method: "DELETE",
			headers,
		});
		expect(signedOut.status).toBe(200);
		expect((await SELF.fetch("https://example.com/api/session", { headers })).status).toBe(401);
	});

	it("supports the POST logout endpoint and revokes only the caller session", async () => {
		const user = await createAccount("logout@example.com");
		const loginResponse = await login(user.email, user.password);
		const { token } = await loginResponse.json() as { token: string };
		const headers = { Authorization: authorizationHeader(token) };

		const logoutResponse = await SELF.fetch("https://example.com/api/auth/logout", {
			method: "POST",
			headers,
		});

		expect(logoutResponse.status).toBe(200);
		expect((await SELF.fetch("https://example.com/api/session", { headers })).status).toBe(401);
	});

it("creates temporary image shares without exposing another user's cloud document", async () => {
		const owner = await createAccount("share-owner@example.com");
		const otherUser = await createAccount("share-other@example.com");
		await env.smartvault_db
			.prepare(
				"INSERT INTO documents (id, user_id, title, category) VALUES (?, ?, ?, ?)",
			)
			.bind("owner-document", owner.id, "Passport", "Passeport")
			.run();

		const ownerLogin = await login(owner.email, owner.password);
		const ownerToken = (await ownerLogin.json() as { token: string }).token;
		const otherLogin = await login(otherUser.email, otherUser.password);
		const otherToken = (await otherLogin.json() as { token: string }).token;
		const originalFetch = globalThis.fetch;
		let imageUploadCount = 0;
		vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
			const requestUrl = String(input);
			if (requestUrl === "https://upload.imagekit.io/api/v1/files/upload") {
				imageUploadCount += 1;
				const side = imageUploadCount === 1 ? "front" : "back";
				return new Response(JSON.stringify({
					filePath: `/smartvault-shares/share-${side}-test.jpg`,
					fileId: `imagekit-share-${side}-test`,
				}), { status: 200, headers: { "Content-Type": "application/json" } });
			}
			if (requestUrl.startsWith("https://api.imagekit.io/v1/files/") && init?.method === "DELETE") {
				return new Response(null, { status: 204 });
			}
			if (requestUrl.startsWith("https://images.example.test/")) {
				return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
			}
			return originalFetch(input, init);
		}));
		Object.assign(env, {
			IMAGEKIT_PRIVATE_KEY: "test-imagekit-private-key",
			IMAGEKIT_URL_ENDPOINT: "https://images.example.test",
		});
		const shareRequest = {
			document_id: "owner-document",
			duration_minutes: 15,
			fields: { category: "Passeport" },
			front_image_base64: "AQID",
			front_image_mime_type: "image/jpeg",
			back_image_base64: "BAUG",
			back_image_mime_type: "image/jpeg",
		};
		const foreignShare = await SELF.fetch("https://example.com/api/shares", {
			method: "POST",
			headers: {
				Authorization: authorizationHeader(otherToken),
				"Content-Type": "application/json",
			},
			body: JSON.stringify(shareRequest),
		});
		expect(foreignShare.status).toBe(404);

		const shareResponse = await SELF.fetch("https://example.com/api/shares", {
			method: "POST",
			headers: {
				Authorization: authorizationHeader(ownerToken),
				"Content-Type": "application/json",
			},
			body: JSON.stringify(shareRequest),
		});
		expect(shareResponse.status).toBe(201);
		const shareBody = await shareResponse.json() as {
			share: { id: string; url: string };
		};

		const foreignRevoke = await SELF.fetch(
			`https://example.com/api/shares/${shareBody.share.id}`,
			{
				method: "DELETE",
				headers: { Authorization: authorizationHeader(otherToken) },
			},
		);
		expect(foreignRevoke.status).toBe(404);

		const openResponse = await SELF.fetch("https://example.com/api/shares/open", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ token: shareBody.share.url.split("#")[1] }),
		});
		expect(openResponse.status).toBe(200);
		expect(await openResponse.json()).toMatchObject({
			success: true,
			fields: { category: "Passeport" },
			images: ["front", "back"],
		});
		expect(imageUploadCount).toBe(2);

		const imageResponse = await SELF.fetch("https://example.com/api/shares/image/front", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ token: shareBody.share.url.split("#")[1] }),
		});
		expect(imageResponse.status).toBe(200);
		expect(Array.from(new Uint8Array(await imageResponse.arrayBuffer()))).toEqual([1, 2, 3]);

		const backImageResponse = await SELF.fetch("https://example.com/api/shares/image/back", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ token: shareBody.share.url.split("#")[1] }),
		});
		expect(backImageResponse.status).toBe(200);
		expect(Array.from(new Uint8Array(await backImageResponse.arrayBuffer()))).toEqual([1, 2, 3]);

		const ownerRevoke = await SELF.fetch(
			`https://example.com/api/shares/${shareBody.share.id}`,
			{ method: "DELETE", headers: { Authorization: authorizationHeader(ownerToken) } },
		);
		expect(ownerRevoke.status).toBe(200);
		const revokedImage = await SELF.fetch("https://example.com/api/shares/image/front", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ token: shareBody.share.url.split("#")[1] }),
		});
		expect(revokedImage.status).toBe(404);
		const revokedBackImage = await SELF.fetch("https://example.com/api/shares/image/back", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ token: shareBody.share.url.split("#")[1] }),
		});
		expect(revokedBackImage.status).toBe(404);
		vi.unstubAllGlobals();
	});

	it("keeps classification requests in D1 without photos and logs Admin decisions", async () => {
		const user = await createAccount("classification-user@example.com");
		const userLogin = await login(user.email, user.password);
		const userToken = (await userLogin.json() as { token: string }).token;
		const requestId = crypto.randomUUID();
		const createResponse = await SELF.fetch(
			"https://example.com/api/classification-requests",
			{
				method: "POST",
				headers: {
					Authorization: authorizationHeader(userToken),
					"Content-Type": "application/json",
				},
				body: JSON.stringify({
					id: requestId,
					title: "Passport",
					document_type: "PASSPORT",
					image_mime_type: "image/jpeg",
					image_base64: "ignored-image-data",
				}),
			},
		);
		expect(createResponse.status).toBe(201);

		const storedRequest = await env.smartvault_db
			.prepare(
				"SELECT image_key, image_mime_type FROM classification_requests WHERE id = ?",
			)
			.bind(requestId)
			.first<{ image_key: string; image_mime_type: string }>();
		expect(storedRequest).toEqual({ image_key: "", image_mime_type: "" });

		const admin = await createAccount("classification-admin@example.com", true);
		const adminLogin = await login(admin.email, admin.password);
		const adminToken = (await adminLogin.json() as { token: string }).token;
		const photoResponse = await SELF.fetch(
			`https://example.com/api/admin/classification-requests/${requestId}/photo`,
			{ headers: { Authorization: authorizationHeader(adminToken) } },
		);
		expect(photoResponse.status).toBe(503);
		expect(await photoResponse.json()).toEqual({
			success: false,
			error: "Classification photo storage is not available.",
		});

		const decisionResponse = await SELF.fetch(
			`https://example.com/api/admin/classification-requests/${requestId}/decision`,
			{
				method: "POST",
				headers: {
					Authorization: authorizationHeader(adminToken),
					"Content-Type": "application/json",
				},
				body: JSON.stringify({
					decision: "accept",
					security_level: "HIGH",
					category: "Passeport",
				}),
			},
		);
		expect(decisionResponse.status).toBe(200);

		const historyResponse = await SELF.fetch(
			"https://example.com/api/admin/classification-history",
			{ headers: { Authorization: authorizationHeader(adminToken) } },
		);
		expect(historyResponse.status).toBe(200);
		expect(await historyResponse.json()).toMatchObject({
			success: true,
			history: [
				{ request_id: requestId, admin_email: admin.email, action: "ADMIN_REVIEWED" },
			],
		});
	});

	it("marks expired pending classification requests when Admin loads the inbox", async () => {
		const admin = await createAccount("classification-expiry-admin@example.com", true);
		const adminLogin = await login(admin.email, admin.password);
		const adminToken = (await adminLogin.json() as { token: string }).token;
		const requestId = crypto.randomUUID();
		await env.smartvault_db
			.prepare(
				`INSERT INTO classification_requests
				 (id, user_id, user_email, title, document_type, image_key,
				  image_mime_type, status, expires_at)
				 VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)`,
			)
			.bind(
				requestId,
				"expired-request-owner",
				"owner@example.com",
				"Expired document",
				"PASSPORT",
				"",
				"",
				new Date(Date.now() - 60_000).toISOString(),
			)
			.run();

		const response = await SELF.fetch(
			"https://example.com/api/admin/classification-requests",
			{ headers: { Authorization: authorizationHeader(adminToken) } },
		);
		expect(response.status).toBe(200);
		expect((await response.json() as { requests: unknown[] }).requests).toEqual([]);

		const expired = await env.smartvault_db
			.prepare("SELECT status, rejection_reason FROM classification_requests WHERE id = ?")
			.bind(requestId)
			.first<{ status: string; rejection_reason: string }>();
		expect(expired).toEqual({
			status: "REJECTED",
			rejection_reason: "Request expired",
		});
	});

	it("grants Admin only to the D1-linked account identity", async () => {
		const admin = await createAccount("admin@example.com", true);
		const response = await login(admin.email, admin.password);
		const body = await response.json() as { token: string; isAdmin: boolean };
		expect(body.isAdmin).toBe(true);

		const inbox = await SELF.fetch("https://example.com/api/admin/classification-requests", {
			headers: { Authorization: `Bearer ${body.token}` },
		});
		expect(inbox.status).toBe(200);
	});

	it("rejects incorrect passwords without revealing whether the account exists", async () => {
		const user = await createAccount("wrong-password@example.com");
		const knownAccount = await login(user.email, "incorrect-password");
		const unknownAccount = await login("missing@example.com", "incorrect-password");

		expect(knownAccount.status).toBe(401);
		expect(await knownAccount.json()).toEqual(await unknownAccount.json());
	});

	it("allows authorization headers in CORS preflight requests", async () => {
		const response = await SELF.fetch("https://example.com/api/documents", {
			method: "OPTIONS",
		});
		expect(response.headers.get("Access-Control-Allow-Headers")).toContain(
			"Authorization",
		);
	});

	it("authenticates legacy users with 310000 PBKDF2 iterations and transparently migrates them to 100000", async () => {
		const email = "legacy-user@example.com";
		const password = "legacy-pass-123!";
		const id = crypto.randomUUID();
		const salt = crypto.randomUUID().replaceAll("-", "");
		const legacyHash = await hashPassword(password, salt, 310_000);
		await env.smartvault_db
			.prepare(
				"INSERT INTO auth_users (id, email, display_name, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
			)
			.bind(id, email, "Legacy User", salt, legacyHash, Date.now())
			.run();

		// Login should succeed with legacy password
		const loginResponse = await login(email, password);
		expect(loginResponse.status).toBe(200);

		// Check that the hash has been updated in DB to 100,000 iterations
		const updatedUser = await env.smartvault_db
			.prepare("SELECT password_salt, password_hash FROM auth_users WHERE id = ?")
			.bind(id)
			.first<{ password_salt: string; password_hash: string }>();
		expect(updatedUser).toBeDefined();
		expect(updatedUser?.password_hash).not.toBe(legacyHash);

		// Subsequent login works seamlessly with the new 100k hash
		const secondLogin = await login(email, password);
		expect(secondLogin.status).toBe(200);
	});
});
