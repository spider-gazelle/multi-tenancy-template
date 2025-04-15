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
    owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
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

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
