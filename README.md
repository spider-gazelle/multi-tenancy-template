# Spider-Gazelle Multitenancy Starter

[![CI](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml/badge.svg)](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml)

Production-ready Spider-Gazelle template with PostgreSQL, multi-tenant organizations, and OAuth authentication.

## Features

- PostgreSQL with migrations
- Multi-tenant organizations with permissions (Admin, Manager, User, Viewer)
- User groups with group-based permissions
- Authentication: username/password, Google OAuth, Microsoft OAuth
- OAuth token storage and refresh
- Organization and group invites with email notifications
- Password reset via email
- Domain mapping
- Docker support

## Quick Start

```bash
shards install
cp .env.example .env
# Edit .env with your PG_DATABASE_URL
crystal run src/app.cr
# Visit http://localhost:3000
```

## Web UI

The template includes ready-to-use web pages:

- `/auth/login` - Login page (password + OAuth)
- `/auth/forgot-password` - Password reset request
- `/organizations` - Organizations list and creation
- `/organizations/:id/manage` - Organization member management
- `/organizations/:id/groups` - Groups management

## Authentication

### Username/Password

```crystal
user = Models::User.new(name: "John", email: "john@example.com")
user.password = "secure_password"
user.save!
```

Or use `crystal run create_test_user.cr`

### OAuth Setup

**Google:**

1. Create OAuth credentials at [Google Cloud Console](https://console.developers.google.com)
2. Add redirect URI: `http://localhost:3000/auth/oauth/google/callback`
3. Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`

**Microsoft:**

1. Register app at [Azure Portal](https://portal.azure.com)
2. Add redirect URI: `http://localhost:3000/auth/oauth/microsoft/callback`
3. Set `MICROSOFT_CLIENT_ID` and `MICROSOFT_CLIENT_SECRET` in `.env`

## API Documentation

Generate OpenAPI docs:

```bash
crystal run src/app.cr -- --docs -f openapi.yml
```

## Usage in Controllers

```crystal
class MyController < App::Base
  base "/organizations"

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action)]
  private def find_organization(id : String)
    @current_org = Models::Organization.find!(UUID.new(id))
  end

  getter! current_org : Models::Organization

  @[AC::Route::Filter(:before_action)]
  private def require_admin
    require_permission!(current_org, Permissions::Admin)
  end

  @[AC::Route::GET("/:id/resources")]
  def index : Array(Models::Resource)
    Models::Resource.where(organization_id: current_org.id).to_a
  end
end
```

## Permission Levels

- **Admin** - Full control
- **Manager** - Manage members and resources
- **User** - Create and manage own resources
- **Viewer** - Read-only access

## Database Schema

- `users` - User accounts with password hash
- `auth` - OAuth provider linkages and tokens
- `organizations` - Tenant organizations with subdomain and admin group
- `organization_users` - Membership with permissions
- `organization_invites` - Pending invitations with email notifications
- `groups` - User groups within organizations with permission levels
- `group_users` - Group membership (with group admin flag)
- `group_invites` - Pending group invitations
- `password_reset_tokens` - Secure password reset tokens
- `domains` - Custom domain mappings
- `api_keys` - API key authentication with scopes
- `audit_logs` - Activity audit trail

## Health Check

Health check endpoints for container orchestration:

- `GET /health` - Basic health status
- `GET /health/live` - Liveness probe (app is running)
- `GET /health/ready` - Readiness probe (database connectivity)

## API Key Authentication

API keys provide programmatic access with scoped permissions:

```crystal
# Create API key for a user
api_key, raw_key = Models::ApiKey.create_for_user(
  user,
  "My API Key",
  scopes: ["read", "write"],
  expires_at: Time.utc + 30.days
)
# raw_key is only shown once: "sk_..."

# Authenticate via Authorization header
# Authorization: Bearer sk_...
```

## Audit Logging

Key actions are automatically logged to `audit_logs`:

- User login/logout
- Organization create/update/delete
- Member add/remove
- Invite creation

Access logs in your code:

```crystal
audit_log(
  Models::AuditLog::Actions::CREATE,
  Models::AuditLog::Resources::ORGANIZATION,
  resource_id: org.id,
  organization: org
)
```

## Groups

Groups allow organizing users within an organization with specific permission levels.

### Key Features

- Each organization has an automatic "Administrators" group
- Groups have a permission level (Admin, Manager, User, Viewer)
- Users can belong to multiple groups
- Group admins can manage group membership
- Organization admins can manage all groups
- Invite users to groups via email (auto-adds to organization if needed)

## Email Configuration

For password resets and invites. Email templates are located in `views/emails/`:

- `password_reset.ecr` - Password reset email
- `organization_invite.ecr` - Organization invitation email
- `group_invite.ecr` - Group invitation email

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM_EMAIL=noreply@yourdomain.com
SMTP_FROM_NAME=Spider Gazelle
APP_BASE_URL=http://localhost:3000
```

**Gmail Setup:** Enable 2FA and generate an App Password at https://myaccount.google.com/apppasswords

## Environment Variables

Required:

- `PG_DATABASE_URL` - PostgreSQL connection string

Optional:

- `SG_ENV` - Environment (development/production)
- `SG_SERVER_HOST` - Server host (default: 127.0.0.1)
- `SG_SERVER_PORT` - Server port (default: 3000)
- `COOKIE_SESSION_SECRET` - Session encryption key
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`
- `MICROSOFT_CLIENT_ID` / `MICROSOFT_CLIENT_SECRET`
- `MICROSOFT_TENANT_ID` - For single-tenant Microsoft apps

Email (for password reset and invites):

- `SMTP_HOST` - SMTP server hostname
- `SMTP_PORT` - SMTP server port
- `SMTP_USERNAME` - SMTP authentication username
- `SMTP_PASSWORD` - SMTP authentication password
- `SMTP_FROM_EMAIL` - From email address
- `SMTP_FROM_NAME` - From display name
- `SMTP_TLS` - TLS mode: `starttls` (default), `smtps`, or `none`
- `APP_BASE_URL` - Base URL for email links

Other:

- `PUBLIC_WWW_PATH` - Static files directory (default: `./www`)

## Testing

```bash
crystal spec
# or
./test
```

## License

Do What the Fuck You Want To Public License
