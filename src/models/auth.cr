class App::Models::Auth < ::PgORM::Base
  table :auth

  primary_key :provider, :uid

  # the OAuth2 provider that was used to authenticate
  attribute provider : String
  attribute uid : String

  attribute user_id : UUID
  belongs_to :user

  # OAuth tokens (optional - only for providers that need API access)
  attribute access_token : String?
  attribute refresh_token : String?
  attribute token_type : String?
  attribute token_expires_at : Time?
  attribute token_scope : String?

  include PgORM::Timestamps

  # Check if access token is expired
  def token_expired? : Bool
    if expires_at = token_expires_at
      Time.utc >= expires_at
    else
      true
    end
  end

  # Check if we have a valid access token
  def valid_token? : Bool
    !!access_token && !token_expired?
  end
end
