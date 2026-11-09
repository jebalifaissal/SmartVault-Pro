import { pbkdf2Sync, randomBytes, randomUUID } from "node:crypto";
import { createInterface } from "node:readline/promises";

const args = new Set(process.argv.slice(2));
const valueFor = (name) => {
  const index = process.argv.indexOf(name);
  return index < 0 ? null : process.argv[index + 1] ?? null;
};

function sqlString(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

async function readHiddenPassword(prompt) {
  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== "function") {
    throw new Error("Run this command in an interactive terminal to enter the password safely.");
  }
  process.stdout.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.setEncoding("utf8");
  process.stdin.resume();

  return new Promise((resolve, reject) => {
    let password = "";
    const finish = (error) => {
      process.stdin.off("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write("\n");
      if (error) reject(error);
      else resolve(password);
    };
    const onData = (chunk) => {
      for (const character of chunk) {
        if (character === "\u0003") {
          finish(new Error("Password entry cancelled."));
          return;
        }
        if (character === "\r" || character === "\n") {
          finish();
          return;
        }
        if (character === "\u007f" || character === "\b") {
          password = password.slice(0, -1);
        } else {
          password += character;
        }
      }
    };
    process.stdin.on("data", onData);
  });
}

const email = valueFor("--email")?.trim().toLowerCase();
const displayName = valueFor("--name")?.trim();
const isAdmin = args.has("--admin");
if (
  !email ||
  !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ||
  !displayName ||
  displayName.length > 120
) {
  console.error(
    "Usage: node scripts/create-account-statement.mjs --email user@example.com --name \"User Name\" [--admin]",
  );
  process.exitCode = 2;
} else {
  const password = await readHiddenPassword("Password (12+ characters): ");
  if (password.length < 12 || password.length > 128) {
    throw new Error("Password must contain between 12 and 128 characters.");
  }
  const salt = randomBytes(16);
  const passwordHash = pbkdf2Sync(password, salt, 100_000, 32, "sha256");
  const id = randomUUID();
  const statement = [
    "BEGIN;",
    `INSERT INTO auth_users (id, email, display_name, password_salt, password_hash, created_at) VALUES (${sqlString(id)}, ${sqlString(email)}, ${sqlString(displayName)}, ${sqlString(salt.toString("hex"))}, ${sqlString(passwordHash.toString("hex"))}, ${Date.now()}) ON CONFLICT(email) DO UPDATE SET display_name = excluded.display_name, password_salt = excluded.password_salt, password_hash = excluded.password_hash;`,
    ...(isAdmin
      ? [
          `INSERT INTO admin_users (email, active, user_id) SELECT ${sqlString(email)}, 1, id FROM auth_users WHERE email = ${sqlString(email)} ON CONFLICT(email) DO UPDATE SET active = 1, user_id = excluded.user_id;`,
        ]
      : []),
    "COMMIT;",
  ].join(" ");
  process.stdout.write(statement);
}
