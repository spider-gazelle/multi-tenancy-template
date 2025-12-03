-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Add OAuth token fields to auth table
ALTER TABLE auth ADD COLUMN access_token TEXT;
ALTER TABLE auth ADD COLUMN refresh_token TEXT;
ALTER TABLE auth ADD COLUMN token_type TEXT DEFAULT 'Bearer';
ALTER TABLE auth ADD COLUMN token_expires_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE auth ADD COLUMN token_scope TEXT;

-- Index for finding expired tokens (useful for cleanup/refresh jobs)
CREATE INDEX idx_auth_token_expires_at ON auth(token_expires_at) WHERE token_expires_at IS NOT NULL;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP INDEX IF EXISTS idx_auth_token_expires_at;
ALTER TABLE auth DROP COLUMN IF EXISTS token_scope;
ALTER TABLE auth DROP COLUMN IF EXISTS token_expires_at;
ALTER TABLE auth DROP COLUMN IF EXISTS token_type;
ALTER TABLE auth DROP COLUMN IF EXISTS refresh_token;
ALTER TABLE auth DROP COLUMN IF EXISTS access_token;
