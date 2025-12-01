# Spider-Gazelle Multitenancy Starter

[![CI](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml/badge.svg)](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml)

Production-ready Spider-Gazelle template with PostgreSQL, multi-tenant organizations, and OAuth authentication.

## Features

- PostgreSQL with migrations
- Multi-tenant organizations with permissions (Admin, Manager, User, Viewer)
- Authentication: username/password, Google OAuth, Microsoft OAuth
- OAuth token storage and refresh
- Organization invites and domain mapping
- Docker support

## Quick Start

```bash
shards install
cp .env.example .env
# Edit .env with your PG_DATABASE_URL
crystal run src/app.cr
# Visit http://localhost:3000
```

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
- `organizations` - Tenant organizations with subdomain
- `organization_users` - Membership with permissions
- `organization_invites` - Pending invitations
- `domains` - Custom domain mappings

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

## Testing

```bash
crystal spec
# or
./test
```

## License

Do What the Fuck You Want To Public License
