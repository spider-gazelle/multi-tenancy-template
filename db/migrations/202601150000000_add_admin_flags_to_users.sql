-- +micrate Up
-- Add support and sys_admin flags to users table
ALTER TABLE users ADD COLUMN support BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN sys_admin BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX idx_users_sys_admin ON users(sys_admin) WHERE sys_admin = true;
CREATE INDEX idx_users_support ON users(support) WHERE support = true;

-- +micrate Down
DROP INDEX IF EXISTS idx_users_support;
DROP INDEX IF EXISTS idx_users_sys_admin;
ALTER TABLE users DROP COLUMN sys_admin;
ALTER TABLE users DROP COLUMN support;
