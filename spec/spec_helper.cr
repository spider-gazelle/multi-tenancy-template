require "spec"
require "uuid/json"
# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

# ensure the database is up to date
require "../src/constants"
require "micrate"
require "pg"
Micrate::DB.connection_url = App::PG_DATABASE_URL
Micrate::Cli.run_status
Micrate::Cli.run_up

# Your application config
require "../src/config"

# Helper methods for tests
def create_user(email : String = "test@example.com", name : String = "Test User") : App::Models::User
  user = App::Models::User.new
  user.name = name
  user.email = email
  user.password = "password123"
  user.save!
  user
end

def create_organization(name : String = "Test Org", subdomain : String? = nil) : App::Models::Organization
  org = App::Models::Organization.new
  org.name = name
  org.subdomain = subdomain
  org.save!
  org
end

def with_auth(user : App::Models::User, &block)
  # Create a session for the user
  session_data = {"user_id" => user.id.to_s}

  # Use the existing curl helper but with session
  with_session(session_data) do
    yield
  end
end

def with_session(session_data : Hash(String, String), &block)
  # This is a simplified version - in a real app you'd need proper session handling
  # For now, we'll just yield and let the tests handle authentication differently
  yield
end

# Clean up before each test
Spec.before_each do
  App::Models::OAuthToken.clear
  App::Models::OAuthClient.clear
  App::Models::AuditLog.clear
  App::Models::ApiKey.clear
  App::Models::PasswordResetToken.clear
  App::Models::GroupInvite.clear
  App::Models::GroupUser.clear
  App::Models::Group.clear
  App::Models::Domain.clear
  App::Models::OrganizationInvite.clear
  App::Models::OrganizationUser.clear
  App::Models::Organization.clear
  App::Models::Auth.clear
  App::Models::User.clear
end
