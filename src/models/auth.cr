require "pg-orm"

class App::Models::Auth < ::PgORM::Base
  table :auth

  # the OAuth2 provider that was used to authenticate
  attribute provider : String
  attribute uid : String

  belongs_to :user

  include PgORM::Timestamps
end
