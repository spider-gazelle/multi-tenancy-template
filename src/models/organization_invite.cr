require "uuid"
require "pg-orm"
require "./converters"
require "./permissions"

class App::Models::OrganizationInvite < ::PgORM::Base
  table :organization_invites

  default_primary_key id : UUID

  # TODO:: additionally add user_id invites
  attribute email : String
  attribute secret : String, mass_assignment: false

  attribute organization_id : UUID
  belongs_to :organization
  attribute permission : App::Permissions, converter: App::PGEnumConverter(App::Permissions)
  attribute expires : Time?

  include PgORM::Timestamps

  validates :email, format: {
    with: /\A[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\z/i,
  }

  # generate a secret for this invite
  before_create { self.secret = UUID.random.to_s }

  def accept!(user : User)
    org = self.organization

    PgORM::Database.transaction do |_tx|
      org.add(user, permission)
      self.destroy
    end
  end

  def self.accept!(id : UUID, secret : String, user : User)
    invite = OrganizationInvite.find(id)
    raise "invite not found" unless invite && invite.secret == secret
    invite.accept! user
  end
end
