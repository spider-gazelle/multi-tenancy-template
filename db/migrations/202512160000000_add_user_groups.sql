-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Groups Table
CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    permission permission NOT NULL DEFAULT 'User',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (organization_id, name)
);

-- Groups table: Faster lookups by organization
CREATE INDEX idx_groups_organization_id ON groups(organization_id);

-- Group Users Table (many-to-many between groups and users)
CREATE TABLE group_users (
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);

-- Group Users table: Faster lookups
CREATE INDEX idx_group_users_user_id ON group_users(user_id);
CREATE INDEX idx_group_users_group_id_admin ON group_users(group_id, is_admin);

-- Group Invites Table
CREATE TABLE group_invites (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    secret TEXT NOT NULL,
    expires TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Group Invites table: Faster lookups
CREATE INDEX idx_group_invites_email ON group_invites(email);
CREATE INDEX idx_group_invites_group_id ON group_invites(group_id);
CREATE INDEX idx_group_invites_expires ON group_invites(expires);

-- Add admin_group_id to organizations table
ALTER TABLE organizations ADD COLUMN admin_group_id UUID REFERENCES groups(id) ON DELETE SET NULL;
CREATE INDEX idx_organizations_admin_group_id ON organizations(admin_group_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP INDEX IF EXISTS idx_organizations_admin_group_id;
ALTER TABLE organizations DROP COLUMN IF EXISTS admin_group_id;

DROP TABLE IF EXISTS group_invites;
DROP TABLE IF EXISTS group_users;
DROP TABLE IF EXISTS groups;