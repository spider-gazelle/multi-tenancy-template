require "uuid"
require "pg-orm"
require "./converters"
require "./permissions"

class App::Models::OrganizationInvite < ::PgORM::Base
  table :organization_invites

  default_primary_key id : UUID

  attribute email : String
  attribute user_id : UUID?
  attribute secret : String, mass_assignment: false

  attribute organization_id : UUID
  belongs_to :organization
  attribute permission : App::Permissions, converter: App::PGEnumConverter(App::Permissions)
  attribute expires : Time?

  include PgORM::Timestamps

  # Get the user if user_id is set
  def user : User?
    if uid = user_id
      User.find?(uid)
    end
  end

  validates :email, format: {
    with: /\A[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\z/i,
  }

  # generate a secret for this invite
  before_create { self.secret = UUID.random.to_s }

  # Check if invite is expired
  def expired? : Bool
    if exp = expires
      Time.utc > exp
    else
      false
    end
  end

  # Check if invite is valid (not expired)
  def valid_invite? : Bool
    !expired?
  end

  def accept!(user : User)
    raise "Invite has expired" if expired?

    # Verify the invite is for this user (if user_id is set)
    if uid = user_id
      raise "This invite is for a different user" unless uid == user.id
    else
      # For email-based invites, verify email matches
      # This prevents someone from accepting an invite meant for someone else
      raise "Email does not match invite" unless user.email.downcase == email.downcase
    end

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
