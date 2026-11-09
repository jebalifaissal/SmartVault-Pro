ALTER TABLE documents ADD COLUMN security_level TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE documents ADD COLUMN classification_status TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE documents ADD COLUMN classification_source TEXT NOT NULL DEFAULT 'AUTOMATIC';

UPDATE documents
SET security_level = CASE
      WHEN category IN ('Pièce d’identité', 'Passeport', 'Permis de conduire')
        THEN 'HIGH'
      WHEN category IN ('Diplôme', 'Cours', 'Notes', 'Informations')
        THEN 'MEDIUM'
      ELSE 'PENDING'
    END,
    classification_status = CASE
      WHEN category IN (
        'Pièce d’identité', 'Passeport', 'Permis de conduire',
        'Diplôme', 'Cours', 'Notes', 'Informations'
      ) THEN 'AUTO_CLASSIFIED'
      ELSE 'PENDING'
    END;

CREATE TABLE IF NOT EXISTS admin_users (
  email TEXT PRIMARY KEY NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS classification_requests (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  user_email TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT,
  document_type TEXT NOT NULL,
  image_key TEXT NOT NULL,
  image_mime_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'ADMIN_REVIEWED', 'REJECTED')),
  security_level TEXT,
  category TEXT,
  rejection_reason TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL,
  decided_at TEXT,
  decided_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_classification_requests_status_created
ON classification_requests(status, created_at);

CREATE INDEX IF NOT EXISTS idx_classification_requests_user_created
ON classification_requests(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS admin_logs (
  id TEXT PRIMARY KEY NOT NULL,
  admin_email TEXT NOT NULL,
  request_id TEXT NOT NULL,
  action TEXT NOT NULL,
  details TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO admin_users (email) VALUES ('admin@gmail.com');
