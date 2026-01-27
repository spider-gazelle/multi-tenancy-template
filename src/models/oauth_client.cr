require "uuid/json"
require "crypto/bcrypt/password"

class App::Models::OAuthClient < ::PgORM::Base
  table :oauth_clients

  primary_key :id

  attribute id : UUID
  attribute name : String
  attribute secret_hash : String?
  attribute redirect_uris : Array(String)
  attribute scopes : Array(String)
  attribute grant_types : Array(String)
  attribute organization_id : UUID?
  attribute active : Bool = true

  include PgORM::Timestamps

  belongs_to :organization

  # Set secret (hashes it automatically)
  def secret=(new_secret : String)
    @secret_hash = Crypto::Bcrypt::Password.create(new_secret).to_s
  end

  # Verify secret
  def verify_secret(secret : String) : Bool
    return false unless hash = secret_hash
    Crypto::Bcrypt::Password.new(hash).verify(secret)
  end

  # Check if client is active
  def active? : Bool
    active
  end
end
