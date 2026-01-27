-- +micrate Up
-- OAuth Clients table
CREATE TABLE oauth_clients (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(255) NOT NULL,
    secret_hash VARCHAR(255),
    redirect_uris TEXT[] NOT NULL DEFAULT '{}',
    scopes TEXT[] NOT NULL DEFAULT '{}',
    grant_types TEXT[] NOT NULL DEFAULT '{}',
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_oauth_clients_active ON oauth_clients(active);
CREATE INDEX idx_oauth_clients_organization_id ON oauth_clients(organization_id);

-- OAuth Tokens table
CREATE TABLE oauth_tokens (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    token TEXT NOT NULL UNIQUE,
    token_type VARCHAR(50) NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    client_id UUID REFERENCES oauth_clients(id) ON DELETE CASCADE,
    scopes TEXT[] NOT NULL DEFAULT '{}',
    expires_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_oauth_tokens_token ON oauth_tokens(token);
CREATE INDEX idx_oauth_tokens_user_id ON oauth_tokens(user_id);
CREATE INDEX idx_oauth_tokens_client_id ON oauth_tokens(client_id);
CREATE INDEX idx_oauth_tokens_expires_at ON oauth_tokens(expires_at);
CREATE INDEX idx_oauth_tokens_revoked_at ON oauth_tokens(revoked_at);

-- +micrate Down
DROP TABLE IF EXISTS oauth_tokens;
DROP TABLE IF EXISTS oauth_clients;
