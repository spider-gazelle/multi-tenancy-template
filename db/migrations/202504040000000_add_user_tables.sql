-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Permission Enum
CREATE TYPE permission AS ENUM ('Admin', 'Manager', 'User', 'Viewer');

-- Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Auth Table
CREATE TABLE auth (
    provider TEXT NOT NULL,
    uid TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (provider, uid)
);

-- Auth table: Faster lookups by user_id
CREATE INDEX idx_auth_user_id ON auth(user_id);

-- Organizations Table
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Organizations table: Faster lookups by owner_id
CREATE INDEX idx_organizations_owner_id ON organizations(owner_id);

-- OrganizationUsers Table
CREATE TABLE organization_users (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    permission permission NOT NULL DEFAULT 'User',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (user_id, organization_id)
);

-- OrganizationUsers table: Faster organization membership lookups
-- Composite primary key (user_id, organization_id) optimizes queries on both columns or the first column alone.
CREATE INDEX idx_org_users_organization_id ON organization_users(organization_id);

-- OrganizationInvites Table
CREATE TABLE organization_invites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    secret TEXT NOT NULL,
    permission permission NOT NULL DEFAULT 'User',
    expires TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- OrganizationInvites table: Faster lookups by email and organization
CREATE INDEX idx_org_invites_email ON organization_invites(email);
CREATE INDEX idx_org_invites_organization_id ON organization_invites(organization_id);
CREATE INDEX idx_org_invites_expires ON organization_invites(expires);

-- Trigger function to automatically update 'updated_at' timestamp
-- +micrate StatementBegin
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +micrate StatementEnd

-- Add triggers to automatically update 'updated_at' on modification
CREATE TRIGGER update_users_timestamp
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_auth_timestamp
BEFORE UPDATE ON auth
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_organizations_timestamp
BEFORE UPDATE ON organizations
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_organization_users_timestamp
BEFORE UPDATE ON organization_users
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_organization_invites_timestamp
BEFORE UPDATE ON organization_invites
FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
