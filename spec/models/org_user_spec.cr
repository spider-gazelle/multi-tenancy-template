require "../spec_helper"

describe App::Models::OrganizationUser do
  org_user = App::Models::OrganizationUser.new
  org = App::Models::Organization.new
  user = App::Models::User.new

  Spec.around_each do |test|
    org_user = App::Models::OrganizationUser.new
    org = App::Models::Organization.new
    org.name = "Testing"
    org.save!

    user = App::Models::User.new
    user.name = "Testing"
    user.email = "steve@orguser.com"
    user.save!

    test.run

    org_user.destroy
    org.destroy
    user.destroy
  end

  it "should be able to associate a user with an organisation" do
    org_user.user = user
    org_user.organization = org
    org_user.permission = App::Permissions::Admin
    org_user.save!
  end
end
