require "spec"

# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

# ensure the database is up to date
require "../src/constants"
require "micrate"
require "pg"
Micrate::DB.connection_url = App::PG_DATABASE_URL
Micrate::Cli.run_status
Micrate::Cli.run_up

Spec.before_each do
  App::Models::User.clear
  App::Models::Auth.clear
  App::Models::Domain.clear
  App::Models::Organization.clear
  App::Models::Oauth2Provider.clear
  App::Models::OrganizationUser.clear
  App::Models::OrganizationInvite.clear
  WebMock.reset
end

# mock API requests
require "webmock"

# Your application config
require "../src/config"
