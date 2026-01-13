-- +micrate Up
ALTER TABLE organization_invites ADD COLUMN user_id UUID REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX idx_org_invites_user_id ON organization_invites(user_id);

-- +micrate Down
DROP INDEX idx_org_invites_user_id;
ALTER TABLE organization_invites DROP COLUMN user_id;
