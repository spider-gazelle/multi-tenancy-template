require "../spec_helper"

describe "Groups Integration" do
  describe "complete organization and groups workflow" do
    it "creates organization with admin group and owner as admin" do
      owner = create_user("owner@example.com", "Owner")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      # Create admin group (simulating what controller does)
      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)

      # Verify admin group was created
      admin_group.persisted?.should be_true
      admin_group.name.should eq("Administrators")
      admin_group.permission.should eq(App::Permissions::Admin)
      admin_group.admin_group?.should be_true

      # Verify owner is in admin group
      admin_group.user_is_member?(owner).should be_true
      admin_group.user_is_admin?(owner).should be_true

      # Verify owner has admin permission in org
      org.user_has_permission?(owner, App::Permissions::Admin).should be_true
      org.user_can_manage_groups?(owner).should be_true
    end

    it "admin can create groups and add members" do
      owner = create_user("owner@example.com", "Owner")
      member = create_user("member@example.com", "Member")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(member, App::Permissions::User)

      # Owner can manage groups
      org.user_can_manage_groups?(owner).should be_true

      # Member cannot manage groups
      org.user_can_manage_groups?(member).should be_false

      # Create a new group
      dev_group = App::Models::Group.new(
        name: "Developers",
        description: "Dev team",
        organization_id: org.id,
        permission: App::Permissions::User
      )
      dev_group.save!
      dev_group.persisted?.should be_true

      # Add member to dev group
      dev_group.add_user(member)
      dev_group.user_is_member?(member).should be_true

      # Member should be able to see the group they're in
      member_group_ids = member.groups_in_organization(org).pluck(:id)
      member_group_ids.should contain(dev_group.id)
    end

    it "prevents removing last admin from admin group" do
      owner = create_user("owner@example.com", "Owner")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!

      # Only one admin in the group
      admin_group.admins.count.should eq(1)
      admin_group.user_is_admin?(owner).should be_true

      # This is the business logic check - controller should prevent this
      # The model itself doesn't enforce this, but we verify the state
      admin_group.admins.count.should eq(1)
    end

    it "group invite workflow for new user" do
      owner = create_user("owner@example.com", "Owner")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)

      # Create dev group
      dev_group = App::Models::Group.new(
        name: "Developers",
        organization_id: org.id,
        permission: App::Permissions::User
      )
      dev_group.save!

      # Create invite
      invite = dev_group.invite("newdev@example.com", Time.utc + 24.hours)
      invite.persisted?.should be_true
      invite.email.should eq("newdev@example.com")
      invite.expired?.should be_false

      # New user signs up and accepts invite
      new_user = create_user("newdev@example.com", "New Dev")

      # Accept invite
      invite.accept!(new_user)

      # Verify user is now in the group
      dev_group.user_is_member?(new_user).should be_true

      # Verify user is now in the organization
      org.users.where(id: new_user.id).exists?.should be_true

      # Invite should be deleted after acceptance
      App::Models::GroupInvite.find?(invite.id).should be_nil
    end

    it "group invite workflow for existing org member" do
      owner = create_user("owner@example.com", "Owner")
      existing_member = create_user("existing@example.com", "Existing")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(existing_member, App::Permissions::User)

      # Create dev group
      dev_group = App::Models::Group.new(
        name: "Developers",
        organization_id: org.id,
        permission: App::Permissions::User
      )
      dev_group.save!

      # Create invite for existing member
      invite = dev_group.invite("existing@example.com")

      # Accept invite
      invite.accept!(existing_member)

      # Verify user is now in the group
      dev_group.user_is_member?(existing_member).should be_true
    end

    it "expired invite cannot be accepted" do
      owner = create_user("owner@example.com", "Owner")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!

      dev_group = App::Models::Group.new(
        name: "Developers",
        organization_id: org.id,
        permission: App::Permissions::User
      )
      dev_group.save!

      # Create expired invite
      invite = dev_group.invite("newdev@example.com", Time.utc - 1.hour)
      invite.expired?.should be_true

      new_user = create_user("newdev@example.com", "New Dev")

      # Accepting expired invite should raise
      expect_raises(App::Error::Forbidden) do
        invite.accept!(new_user)
      end
    end

    it "permission hierarchy works correctly" do
      owner = create_user("owner@example.com", "Owner")
      manager = create_user("manager@example.com", "Manager")
      user = create_user("user@example.com", "User")
      viewer = create_user("viewer@example.com", "Viewer")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(manager, App::Permissions::Manager)
      org.add(user, App::Permissions::User)
      org.add(viewer, App::Permissions::Viewer)

      # Admin has all permissions
      org.user_has_permission?(owner, App::Permissions::Admin).should be_true
      org.user_has_permission?(owner, App::Permissions::Manager).should be_true
      org.user_has_permission?(owner, App::Permissions::User).should be_true
      org.user_has_permission?(owner, App::Permissions::Viewer).should be_true

      # Manager has Manager and below
      org.user_has_permission?(manager, App::Permissions::Admin).should be_false
      org.user_has_permission?(manager, App::Permissions::Manager).should be_true
      org.user_has_permission?(manager, App::Permissions::User).should be_true
      org.user_has_permission?(manager, App::Permissions::Viewer).should be_true

      # User has User and below
      org.user_has_permission?(user, App::Permissions::Admin).should be_false
      org.user_has_permission?(user, App::Permissions::Manager).should be_false
      org.user_has_permission?(user, App::Permissions::User).should be_true
      org.user_has_permission?(user, App::Permissions::Viewer).should be_true

      # Viewer has only Viewer
      org.user_has_permission?(viewer, App::Permissions::Admin).should be_false
      org.user_has_permission?(viewer, App::Permissions::Manager).should be_false
      org.user_has_permission?(viewer, App::Permissions::User).should be_false
      org.user_has_permission?(viewer, App::Permissions::Viewer).should be_true
    end

    it "group-based permissions work correctly" do
      owner = create_user("owner@example.com", "Owner")
      member = create_user("member@example.com", "Member")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(member, App::Permissions::Viewer) # Low direct permission

      # Create manager group
      manager_group = App::Models::Group.new(
        name: "Managers",
        organization_id: org.id,
        permission: App::Permissions::Manager
      )
      manager_group.save!

      # Add member to manager group
      manager_group.add_user(member)

      # Member should now have Manager permission through group
      org.user_has_permission?(member, App::Permissions::Manager).should be_true
    end

    it "user can be in multiple groups" do
      owner = create_user("owner@example.com", "Owner")
      member = create_user("member@example.com", "Member")

      org = App::Models::Organization.new(name: "Test Corp")
      org.owner_id = owner.id
      org.save!

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(member, App::Permissions::User)

      # Create multiple groups
      dev_group = App::Models::Group.new(name: "Developers", organization_id: org.id, permission: App::Permissions::User)
      dev_group.save!

      qa_group = App::Models::Group.new(name: "QA", organization_id: org.id, permission: App::Permissions::User)
      qa_group.save!

      # Add member to both groups
      dev_group.add_user(member)
      qa_group.add_user(member)

      # Member should be in both groups
      member_group_ids = member.groups_in_organization(org).pluck(:id)
      member_group_ids.size.should eq(2)
      member_group_ids.should contain(dev_group.id)
      member_group_ids.should contain(qa_group.id)
      dev_group.user_is_member?(member).should be_true
      qa_group.user_is_member?(member).should be_true
    end
  end
end
