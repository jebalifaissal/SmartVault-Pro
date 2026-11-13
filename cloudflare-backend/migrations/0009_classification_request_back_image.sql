-- Store the optional back side of a submitted classification document.
ALTER TABLE classification_requests ADD COLUMN back_image_key TEXT;
ALTER TABLE classification_requests ADD COLUMN back_image_mime_type TEXT;
