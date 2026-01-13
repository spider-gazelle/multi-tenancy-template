require "random/secure"
require "openssl/hmac"

class App::Models::PasswordResetToken < ::PgORM::Base
  table :password_reset_tokens

  primary_key :id

  attribute id : String
  attribute secret_hash : String
  attribute user_id : UUID
  attribute expires_at : Time
  attribute used_at : Time?

  belongs_to :user

  include PgORM::Timestamps

  before_create :generate_id
  before_create :hash_secret!

  # Store the plain secret temporarily (only available before save)
  property plain_secret : String?

  # Generate a secure random ID
  private def generate_id
    @id ||= Random::Secure.hex(16)
  end

  # Generate a secure random secret
  private def self.generate_secret : String
    Random::Secure.urlsafe_base64(32)
  end

  # Hash the secret before storing
  private def hash_secret!
    return if @plain_secret.nil?
    @secret_hash = OpenSSL::HMAC.hexdigest(:sha512, @plain_secret.not_nil!, @id.not_nil!)
  end

  # Get the full token (only available before save)
  def token : String?
    return nil if persisted?
    "#{@id}.#{@plain_secret}"
  end

  # Create a new password reset token for a user
  # Returns a tuple of {instance, token_string}
  def self.create_for_user(user : User, expires_in : Time::Span = 1.hour) : {PasswordResetToken, String}
    id = Random::Secure.hex(16)
    secret = generate_secret

    instance = new(
      id: id,
      user_id: user.id,
      expires_at: Time.utc + expires_in
    )
    instance.plain_secret = secret

    # Build token string before save
    token_string = "#{id}.#{secret}"

    instance.save!
    {instance, token_string}
  end

  # Find and verify a token
  def self.find_by_token(token : String) : PasswordResetToken?
    parts = token.split('.', 2)
    return nil if parts.size != 2

    id = parts[0]
    secret = parts[1]

    instance = find?(id)
    return nil if instance.nil?

    # Verify the secret matches
    expected_hash = OpenSSL::HMAC.hexdigest(:sha512, secret, id)
    return nil unless instance.secret_hash == expected_hash

    instance
  rescue
    nil
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
