-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- OAuth2 Providers Table
-- Stores generic OAuth2 provider configurations
CREATE TABLE oauth2_providers (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    client_id TEXT NOT NULL,
    client_secret TEXT NOT NULL,
    site TEXT NOT NULL,
    authorize_url TEXT NOT NULL,
    token_url TEXT NOT NULL,
    token_method TEXT NOT NULL DEFAULT 'POST',
    authentication_scheme TEXT NOT NULL DEFAULT 'Request Body',
    user_profile_url TEXT NOT NULL,
    scopes TEXT NOT NULL,
    info_mappings JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- OAuth2 Providers table: Faster lookups by organization_id
CREATE INDEX idx_oauth2_providers_organization_id ON oauth2_providers(organization_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS oauth2_providers;
