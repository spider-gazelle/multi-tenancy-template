require "uuid"
require "pg-orm"
require "./converters"
require "./permissions"

class App::Models::OrganizationInvite < ::PgORM::Base
  table :organization_invites

  default_primary_key id : UUID

  # TODO:: email validation
  # TODO:: additionally add user_id invites
  attribute email : String
  attribute secret : String, mass_assignment: false

  belongs_to :organization
  attribute permission : App::Permissions, converter: App::PGEnumConverter(App::Permissions)
  attribute expires : Time?

  include PgORM::Timestamps

  # generate a secret for this invite
  before_create { self.secret = UUID.random.to_s }

  def accept!
    user = User.where(email: self.email.downcase).first
    org = self.organization

    PgORM::Database.transaction do |_tx|
      org.add(user, permission)
      self.destroy
    end
  end
end
