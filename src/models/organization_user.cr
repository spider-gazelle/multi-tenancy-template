require "./converters"
require "./permissions"

class App::Models::OrganizationUser < ::PgORM::Base
  table :organization_users

  primary_key :user_id, :organization_id

  attribute user_id : UUID
  belongs_to :user

  attribute organization_id : UUID
  belongs_to :organization

  attribute permission : App::Permissions, converter: App::PGEnumConverter(App::Permissions)

  include PgORM::Timestamps
end
