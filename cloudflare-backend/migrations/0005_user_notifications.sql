-- Notifications envoyées aux utilisateurs suite aux décisions admin
CREATE TABLE IF NOT EXISTS user_notifications (
  id          TEXT PRIMARY KEY NOT NULL,
  user_id     TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK(type IN ('document_accepted', 'document_rejected')),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  request_id  TEXT NOT NULL,
  category    TEXT,          -- renseigné si accepté
  security_level TEXT,       -- renseigné si accepté
  is_read     INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_read
  ON user_notifications(user_id, is_read, created_at DESC);
