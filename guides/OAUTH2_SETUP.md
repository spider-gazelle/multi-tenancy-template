# OAuth2 / OpenID Connect Setup

This application uses [Authly](https://github.com/azutoolkit/authly) to provide OAuth2 and OpenID Connect authentication capabilities.

## Endpoints

All OAuth2/OIDC endpoints are mounted at `/auth/oauth/*`:

### Authorization & Token Endpoints

- `GET /auth/oauth/authorize` - Authorization endpoint (OAuth2 authorization code flow)
- `POST /auth/oauth/token` - Token endpoint (exchange codes/credentials for tokens)
- `POST /auth/revoke` - Token revocation endpoint
- `POST /auth/introspect` - Token introspection endpoint

### OpenID Connect Endpoints

- `GET /auth/oauth/userinfo` - UserInfo endpoint (get user claims)
- `GET /auth/.well-known/openid-configuration` - OpenID Connect Discovery

### Device Flow Endpoints

- `POST /auth/oauth/device/code` - Request device code
- `GET /device` - Device verification page

### Advanced Endpoints

- `POST /auth/oauth/par` - Pushed Authorization Requests (PAR)
- `POST /auth/oauth/register` - Dynamic Client Registration (disabled by default)

## Configuration

### JWT Secret

The application requires a JWT secret for signing tokens. The algorithm is auto-detected based on the format:

```bash
# For RS256 (recommended for production):
# Generate RSA key pair:
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# Base64 encode the private key:
JWT_SECRET=$(base64 < private_key.pem)

# For HS256 (simpler, suitable for development):
JWT_SECRET="your-secret-key-here"
```

The application automatically detects:

- **RS256**: If `JWT_SECRET` is a base64-encoded RSA private key (PEM format)
- **HS256**: If `JWT_SECRET` is a plain string

### Issuer

Set the JWT issuer identifier:

```bash
JWT_ISSUER="PlaceOS"  # or your organization name
```

### Token TTLs

Token lifetimes are configured in `src/authly/authly_config.cr`:

```crystal
config.access_ttl = 2.hours    # Access token lifetime
config.refresh_ttl = 30.days   # Refresh token lifetime
config.code_ttl = 10.minutes   # Authorization code lifetime
```

## OAuth2 Clients

### Creating a Client

OAuth2 clients must be registered in the database:

```crystal
client = App::Models::OAuthClient.new(
  id: "my-client-id",
  name: "My Application",
  redirect_uris: ["https://myapp.com/callback"],
  scopes: ["read", "write", "org:abc123:manager"],
  grant_types: ["authorization_code", "refresh_token"],
  active: true
)
client.secret = "my-client-secret"  # Will be hashed
client.save!
```

### Scopes

Scopes can be:

- **Generic:** `read`, `write`, `admin`, etc.
- **Organization-specific:** `org:{org_id}:admin`, `org:{org_id}:manager`, `org:{org_id}:user`, `org:{org_id}:viewer`
- **Resource-based:** `organizations.read`, `organizations.write`

Organization-specific scopes grant permissions in that organization. Generic permission scopes (`admin`, `manager`, etc.) apply to all organizations the user has access to.

### Client Authentication

Clients authenticate using HTTP Basic Auth or POST body:

```bash
# Basic Auth
curl -X POST https://yourapp.com/auth/oauth/token \
  -u "client_id:client_secret" \
  -d "grant_type=authorization_code&code=AUTH_CODE&redirect_uri=..."

# POST body
curl -X POST https://yourapp.com/auth/oauth/token \
  -d "grant_type=authorization_code" \
  -d "client_id=CLIENT_ID" \
  -d "client_secret=CLIENT_SECRET" \
  -d "code=AUTH_CODE" \
  -d "redirect_uri=..."
```

## Grant Types

### Authorization Code Flow

1. Redirect user to authorization endpoint:

```
GET /auth/oauth/authorize?
  response_type=code&
  client_id=CLIENT_ID&
  redirect_uri=REDIRECT_URI&
  scope=public read&
  state=RANDOM_STATE
```

2. User authenticates and authorizes

3. Redirect back with authorization code:

```
https://yourapp.com/callback?code=AUTH_CODE&state=RANDOM_STATE
```

4. Exchange code for tokens:

```bash
POST /auth/oauth/token
  grant_type=authorization_code
  code=AUTH_CODE
  redirect_uri=REDIRECT_URI
  client_id=CLIENT_ID
  client_secret=CLIENT_SECRET
```

### Client Credentials Flow

For server-to-server authentication:

```bash
POST /auth/oauth/token
  grant_type=client_credentials
  client_id=CLIENT_ID
  client_secret=CLIENT_SECRET
  scope=public read
```

### Resource Owner Password Flow

For trusted first-party applications:

```bash
POST /auth/oauth/token
  grant_type=password
  username=USER_EMAIL
  password=USER_PASSWORD
  client_id=CLIENT_ID
  client_secret=CLIENT_SECRET
```

### Refresh Token Flow

To get a new access token:

```bash
POST /auth/oauth/token
  grant_type=refresh_token
  refresh_token=REFRESH_TOKEN
  client_id=CLIENT_ID
  client_secret=CLIENT_SECRET
```

## PKCE Support

For public clients (SPAs, mobile apps), use PKCE:

1. Generate code verifier and challenge:

```crystal
verifier = Random::Secure.hex(32)
challenge = Digest::SHA256.base64digest(verifier)
```

2. Authorization request with PKCE:

```
GET /auth/oauth/authorize?
  response_type=code&
  client_id=CLIENT_ID&
  redirect_uri=REDIRECT_URI&
  code_challenge=CHALLENGE&
  code_challenge_method=S256&
  state=STATE
```

3. Token exchange with verifier:

```bash
POST /auth/oauth/token
  grant_type=authorization_code
  code=AUTH_CODE
  redirect_uri=REDIRECT_URI
  client_id=CLIENT_ID
  code_verifier=VERIFIER
```

## JWT Token Structure

Access tokens are JWTs with the following structure:

```json
{
  "iss": "PlaceOS",
  "iat": 1640000000,
  "exp": 1640007200,
  "jti": "unique-token-id",
  "sub": "user-uuid",
  "aud": "client-id",
  "scope": ["read", "write"],
  "u": {
    "n": "User Name",
    "e": "user@example.com",
    "p": 0,
    "r": ["org:abc123:admin", "org:def456:user", "group:xyz789"]
  }
}
```

### Claims

- `iss` - Issuer (from `JWT_ISSUER` env var)
- `iat` - Issued at timestamp
- `exp` - Expiration timestamp
- `jti` - JWT ID (unique identifier for revocation)
- `sub` - Subject (user UUID)
- `aud` - Audience (client ID)
- `scope` - Array of OAuth2 scopes
- `u` - User metadata object:
  - `n` - User name
  - `e` - User email
  - `p` - Permission bitflags (bit 0 = support, bit 1 = sys_admin)
  - `r` - Roles array (organization permissions and group memberships)

### Roles Format

The `u.r` array contains:

- `org:{org_id}:{permission}` - Organization-level permission (admin, manager, user, viewer)
- `group:{group_id}` - Group membership

**Example:**

```json
{
  "r": [
    "org:123e4567-e89b-12d3-a456-426614174000:admin",
    "org:987fcdeb-51a2-43f7-8b6d-9c8e7f6a5b4c:user",
    "group:abc12345-6789-0def-1234-567890abcdef"
  ]
}
```

This user is an Admin in one organization, a User in another, and belongs to a specific group.

## Token Introspection

Validate and inspect tokens:

```bash
POST /auth/introspect
  token=ACCESS_TOKEN
```

Response:

```json
{
  "active": true,
  "cid": "CLIENT_ID",
  "sub": "user-uuid",
  "scope": "read write",
  "exp": 1640007200
}
```

## Token Revocation

Revoke access or refresh tokens:

```bash
POST /auth/revoke
  token=TOKEN_TO_REVOKE
```

## OpenID Connect

### UserInfo Endpoint

Get user information using an access token:

```bash
GET /auth/oauth/userinfo
Authorization: Bearer ACCESS_TOKEN
```

Response:

```json
{
  "sub": "user-uuid",
  "name": "User Name",
  "email": "user@example.com"
}
```

### Discovery

OpenID Connect discovery metadata:

```bash
GET /auth/.well-known/openid-configuration
```

## Security Features

### PKCE Enforcement

Enable PKCE requirement in `src/authly/authly_config.cr`:

```crystal
config.enforce_pkce = true          # Require PKCE for all flows
config.enforce_pkce_s256 = true     # Enforce S256 method only
```

### Certificate-Bound Tokens (mTLS)

Enable certificate-bound tokens:

```crystal
config.require_certificate_bound_tokens = true
config.trusted_ca_certificates = [
  File.read("path/to/ca.pem")
]
```

## Database Schema

### OAuth Clients Table

```sql
CREATE TABLE oauth_clients (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    secret_hash VARCHAR(255),
    redirect_uris TEXT[] NOT NULL DEFAULT '{}',
    scopes TEXT[] NOT NULL DEFAULT '{}',
    grant_types TEXT[] NOT NULL DEFAULT '{}',
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_oauth_clients_active ON oauth_clients(active);
```

### OAuth Tokens Table

```sql
CREATE TABLE oauth_tokens (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    token TEXT NOT NULL UNIQUE,
    token_type VARCHAR(50) NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    client_id VARCHAR(255) REFERENCES oauth_clients(id) ON DELETE CASCADE,
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
```

## Troubleshooting

### JWT_SECRET not set

Error: `JWT_SECRET environment variable required for OAuth2/OIDC`

Solution: Set `JWT_SECRET` in your `.env` file.

### Invalid redirect_uri

Error: `redirect_uri is not registered for this client`

Solution: Ensure the redirect URI is registered in the `oauth_clients.redirect_uris` array.

### Token expired

Error: `Token has expired`

Solution: Use the refresh token to get a new access token, or re-authenticate.

### Algorithm Detection

The application automatically detects the JWT signing algorithm:

- If `JWT_SECRET` contains a base64-encoded PEM key (with "BEGIN" marker), it uses **RS256**
- Otherwise, it uses **HS256** with the plain string as the secret

To verify which algorithm is being used, check the application logs on startup.
