-- Additive migration; run before loading the clipboard-enabled server version.
ALTER TABLE users ADD COLUMN IF NOT EXISTS clipboard_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS clipboard_revision BIGINT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS clipboard_expires_at BIGINT;
CREATE UNIQUE INDEX IF NOT EXISTS ix_clipboard_latest ON messages(user_id,clipboard_revision);
