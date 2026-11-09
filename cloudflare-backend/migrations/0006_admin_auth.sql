-- Migration 0006 : Authentification admin indépendante
-- Ajoute le hachage de mot de passe sur admin_users
-- et une table de sessions dédiée aux admins.

ALTER TABLE admin_users ADD COLUMN password_salt TEXT;
ALTER TABLE admin_users ADD COLUMN password_hash TEXT;

-- Sessions admin : séparées des sessions utilisateurs normaux
-- pour qu'un token admin ne puisse jamais être utilisé comme token user.
CREATE TABLE IF NOT EXISTS admin_sessions (
  token_hash  TEXT    PRIMARY KEY NOT NULL,
  admin_email TEXT    NOT NULL REFERENCES admin_users(email) ON DELETE CASCADE,
  expires_at  INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  revoked_at  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_email_expires
  ON admin_sessions(admin_email, expires_at);

-- Rate-limiting des tentatives de connexion admin (par IP, fenêtre 15 min)
CREATE TABLE IF NOT EXISTS admin_login_attempts (
  key_hash     TEXT    PRIMARY KEY NOT NULL,
  attempts     INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);
