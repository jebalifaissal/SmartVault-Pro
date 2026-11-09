ALTER TABLE documents ADD COLUMN user_id TEXT;
ALTER TABLE documents ADD COLUMN holder_name TEXT;
ALTER TABLE documents ADD COLUMN document_number TEXT;
ALTER TABLE documents ADD COLUMN expiry_date TEXT;
ALTER TABLE documents ADD COLUMN name TEXT;
ALTER TABLE documents ADD COLUMN surname TEXT;
ALTER TABLE documents ADD COLUMN date_of_birth TEXT;
ALTER TABLE documents ADD COLUMN place_of_birth TEXT;
ALTER TABLE documents ADD COLUMN image_storage_path TEXT;
ALTER TABLE documents ADD COLUMN document_type TEXT;
ALTER TABLE documents ADD COLUMN full_name TEXT;
ALTER TABLE documents ADD COLUMN first_name TEXT;
ALTER TABLE documents ADD COLUMN last_name TEXT;
ALTER TABLE documents ADD COLUMN cin_number TEXT;
ALTER TABLE documents ADD COLUMN expiration_date TEXT;
ALTER TABLE documents ADD COLUMN updated_at TEXT;
ALTER TABLE documents ADD COLUMN status TEXT;

CREATE INDEX IF NOT EXISTS idx_documents_user_created
ON documents(user_id, created_at DESC);
