require "../spec_helper"

describe App::Models::GroupInvite do
  it "should create a group invite" do
    org = create_organization
    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    invite = App::Models::GroupInvite.new(
      email: "test@example.com",
      secret: "secret123",
      group_id: group.id
    )

    invite.save!
    invite.persisted?.should be_true
    invite.email.should eq("test@example.com")
  end

  pending "should validate email format"

  it "should check expiration" do
    org = create_organization
    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    # Non-expired invite
    invite1 = App::Models::GroupInvite.new(
      email: "test1@example.com",
      secret: "secret123",
      group_id: group.id,
      expires: Time.utc + 1.hour
    )
    invite1.save!
    invite1.expired?.should be_false
    invite1.invite_valid?.should be_true

    # Expired invite
    invite2 = App::Models::GroupInvite.new(
      email: "test2@example.com",
      secret: "secret456",
      group_id: group.id,
      expires: Time.utc - 1.hour
    )
    invite2.save!
    invite2.expired?.should be_true
    invite2.invite_valid?.should be_false
  end

  it "should accept invite for existing user" do
    org = create_organization
    user = create_user("test@example.com")

    # Add user to organization first
    org.add(user, App::Permissions::User)

    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    invite = App::Models::GroupInvite.new(
      email: user.email,
      secret: "secret123",
      group_id: group.id
    )
    invite.save!

    accepted_user = invite.accept!(user)

    accepted_user.should eq(user)
    group.user_is_member?(user).should be_true

    # Invite should be deleted
    App::Models::GroupInvite.find?(invite.id).should be_nil
  end

  it "should fail to accept expired invite" do
    org = create_organization
    user = create_user("test@example.com")
    org.add(user, App::Permissions::User)

    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    invite = App::Models::GroupInvite.new(
      email: user.email,
      secret: "secret123",
      group_id: group.id,
      expires: Time.utc - 1.hour
    )
    invite.save!

    expect_raises(Exception, "Invite has expired") do
      invite.accept!(user)
    end
  end
end
