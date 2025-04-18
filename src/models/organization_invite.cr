require "uuid"
require "pg-orm"
require "./converters"
require "./permissions"

class App::Models::OrganizationInvite < ::PgORM::Base
  table :organization_invites

  default_primary_key id : UUID

  # TODO:: email validation
  attribute email : String
  attribute secret : String, mass_assignment: false

  belongs_to :organization
  attribute permission : App::Permissions, converter: App::PGEnumConverter(App::Permissions)
  attribute expires : Time?

  include PgORM::Timestamps

  # generate a secret for this invite
  before_create { self.secret = UUID.random.to_s }
end
