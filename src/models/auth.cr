class App::Models::Auth < ::PgORM::Base
  table :auth

  primary_key :provider, :uid

  # the OAuth2 provider that was used to authenticate
  attribute provider : String
  attribute uid : String

  attribute user_id : UUID
  belongs_to :user

  include PgORM::Timestamps
end
