require "random/secure"

class App::Models::PasswordResetToken < ::PgORM::Base
  table :password_reset_tokens

  primary_key :token

  attribute token : String
  attribute user_id : UUID
  attribute expires_at : Time
  attribute used_at : Time?

  belongs_to :user

  include PgORM::Timestamps

  # Generate a secure random token
  def self.generate_token : String
    Random::Secure.hex(32)
  end

  # Create a new password reset token for a user
  def self.create_for_user(user : User, expires_in : Time::Span = 1.hour) : PasswordResetToken
    token = new(
      token: generate_token,
      user_id: user.id,
      expires_at: Time.utc + expires_in
    )
    token.save!
    token
  end

  # Check if token is valid (not expired and not used)
  def valid? : Bool
    used_at.nil? && Time.utc < expires_at
  end

  # Mark token as used
  def mark_as_used!
    self.used_at = Time.utc
    save!
  end
end
