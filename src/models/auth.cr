class App::Models::Auth < ::PgORM::Base
  table :auth

  primary_key :provider, :uid

  # the provider that was used to authenticate
  # i.e. google, apple, microsoft etc
  attribute provider : String
  attribute uid : String

  attribute user_id : UUID
  belongs_to :user

  include PgORM::Timestamps
end
