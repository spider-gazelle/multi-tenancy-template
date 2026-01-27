require "uuid/json"

class App::Models::OAuthToken < ::PgORM::Base
  table :oauth_tokens

  primary_key :id

  attribute id : UUID

  attribute token : String
  attribute token_type : String
  attribute user_id : UUID?
  attribute client_id : UUID?
  attribute scopes : Array(String)
  attribute expires_at : Time
  attribute revoked_at : Time?
  attribute metadata : Hash(String, String) = {} of String => String

  include PgORM::Timestamps

  # Find token by token string
  def self.find_by_token?(token : String) : OAuthToken?
    where(token: token).first?
  end

  # Check if token is expired
  def expired? : Bool
    Time.utc >= expires_at
  end

  # Check if token is revoked
  def revoked? : Bool
    !revoked_at.nil?
  end

  # Check if token is valid (not expired and not revoked)
  def token_valid? : Bool
    !expired? && !revoked?
  end
end
