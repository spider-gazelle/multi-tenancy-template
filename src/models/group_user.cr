class App::Models::GroupUser < ::PgORM::Base
  table :group_users

  primary_key :group_id, :user_id

  attribute group_id : UUID
  belongs_to :group

  attribute user_id : UUID
  belongs_to :user

  attribute is_admin : Bool

  include PgORM::Timestamps
end
