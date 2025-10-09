require "../spec_helper"

describe App::Models::OrganizationInvite do
  org = App::Models::Organization.new
  user = App::Models::User.new
  invite = App::Models::OrganizationInvite.new

  Spec.before_each do
    org.destroy rescue nil
    user.destroy rescue nil
    invite.destroy rescue nil
    org = App::Models::Organization.new
    user = App::Models::User.new
    invite = App::Models::OrganizationInvite.new
  end

  it "should be able to invite a user to an organization" do
    org.name = "Testing"
    org.save!

    invite.email = "test@test.com"
    invite.permission = App::Permissions::Viewer
    invite.organization = org
    invite.save!
    invite.secret.nil?.should be_false

    user.email = "test@test.com"
    user.name = "testing"
    user.save!

    user.organizations.map(&.id).should_not contain(org.id)

    App::Models::OrganizationInvite.accept!(
      id: invite.id,
      secret: invite.secret,
      user: user,
    )
    user.organizations.map(&.id).should contain(org.id)
  end
end
