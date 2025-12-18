require "../spec_helper"

describe App::Models::Group do
  it "should create a group" do
    org = create_organization

    group = App::Models::Group.new(
      name: "Developers",
      description: "Development team",
      permission: App::Permissions::User,
      organization_id: org.id
    )

    group.save!
    group.persisted?.should be_true
    group.name.should eq("Developers")
    group.permission.should eq(App::Permissions::User)
  end

  it "should validate uniqueness of name within organization" do
    org = create_organization

    # Create first group
    group1 = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group1.save!
    group1.persisted?.should be_true

    # Try to create second group with same name in same org
    group2 = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::Manager
    )

    # This should fail due to database unique constraint
    expect_raises(Exception) do
      group2.save!
    end
  end

  it "should allow same name in different organizations" do
    org1 = create_organization
    org2 = create_organization("Org 2")

    group1 = App::Models::Group.new(
      name: "Developers",
      organization_id: org1.id,
      permission: App::Permissions::User
    )
    group1.save!
    group1.persisted?.should be_true

    group2 = App::Models::Group.new(
      name: "Developers",
      organization_id: org2.id,
      permission: App::Permissions::User
    )
    group2.save!
    group2.persisted?.should be_true
  end

  it "should add and remove users" do
    org = create_organization
    user = create_user("test@example.com")

    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    # Add user to group
    group.add_user(user, is_admin: true)

    group.user_is_member?(user).should be_true
    group.user_is_admin?(user).should be_true

    # Remove user from group
    group.remove_user(user)
    group.user_is_member?(user).should be_false
  end

  it "should create invites" do
    org = create_organization
    group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    group.save!

    invite = group.invite("newuser@example.com")

    invite.persisted?.should be_true
    invite.email.should eq("newuser@example.com")
    invite.group_id.should eq(group.id)
    invite.secret.should_not be_empty
  end

  it "should identify admin groups" do
    org = create_organization
    admin_group = org.ensure_admin_group!

    regular_group = App::Models::Group.new(
      name: "Developers",
      organization_id: org.id,
      permission: App::Permissions::User
    )
    regular_group.save!

    admin_group.admin_group?.should be_true
    regular_group.admin_group?.should be_false
  end
end
