require "./spec_helper"

describe "End-to-End Integration" do
  describe "complete user registration and organization workflow" do
    it "user signs up, creates org, invites member, member joins" do
      # Step 1: User signs up with password
      owner = App::Models::User.new(name: "Alice Owner", email: "alice@example.com")
      owner.password = "secure123"
      owner.save!
      owner.persisted?.should be_true
      owner.verify_password("secure123").should be_true

      # Step 2: Owner creates an organization
      org = App::Models::Organization.new(name: "Alice's Company", subdomain: "alice-co")
      org.owner_id = owner.id
      org.save!
      org.persisted?.should be_true

      # Step 3: Admin group is created and owner added
      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)

      admin_group.persisted?.should be_true
      admin_group.user_is_member?(owner).should be_true
      org.user_has_permission?(owner, App::Permissions::Admin).should be_true

      # Step 4: Owner invites a new member via email
      invite = org.invite("bob@example.com", App::Permissions::User, Time.utc + 24.hours)
      invite.persisted?.should be_true
      invite.secret.should_not be_empty

      # Step 5: Bob signs up
      bob = App::Models::User.new(name: "Bob Member", email: "bob@example.com")
      bob.password = "bobpass123"
      bob.save!

      # Step 6: Bob accepts the invite
      App::Models::OrganizationInvite.accept!(
        id: invite.id,
        secret: invite.secret,
        user: bob
      )

      # Verify Bob is now in the organization
      bob.organizations.map(&.id).should contain(org.id)
      org.user_has_permission?(bob, App::Permissions::User).should be_true
      org.user_has_permission?(bob, App::Permissions::Admin).should be_false
    end

    it "OAuth user links account and joins organization" do
      # Step 1: User authenticates via OAuth (simulated)
      user = App::Models::User.new(name: "OAuth User", email: "oauth@example.com")
      user.save!

      # Step 2: OAuth auth record is created
      auth = App::Models::Auth.new(
        provider: "google",
        uid: "google-12345",
        user_id: user.id,
        access_token: "ya29.access_token",
        refresh_token: "1//refresh_token",
        token_type: "Bearer",
        token_expires_at: Time.utc + 1.hour
      )
      auth.save!

      user.auth_sources.map(&.provider).should contain("google")
      auth.valid_token?.should be_true

      # Step 3: User creates organization
      org = App::Models::Organization.new(name: "OAuth Org")
      org.owner_id = user.id
      org.save!
      org.create_admin_group!
      org.add(user, App::Permissions::Admin)

      org.user_can_manage_groups?(user).should be_true
    end
  end

  describe "password reset workflow" do
    it "user requests and completes password reset" do
      # Step 1: User exists with password
      user = App::Models::User.new(name: "Forgetful User", email: "forgetful@example.com")
      user.password = "old_password"
      user.save!

      # Step 2: Create password reset token
      reset_token = App::Models::PasswordResetToken.create_for_user(user)
      reset_token.persisted?.should be_true
      reset_token.token.should_not be_empty
      reset_token.valid?.should be_true

      # Step 3: Verify token can be found
      found_token = App::Models::PasswordResetToken.find?(reset_token.token)
      found_token.should_not be_nil
      found_token.not_nil!.user_id.should eq(user.id)

      # Step 4: Reset password
      user.password = "new_password"
      user.save!

      # Step 5: Verify new password works, old doesn't
      user.verify_password("new_password").should be_true
      user.verify_password("old_password").should be_false

      # Step 6: Verify token validity check works
      reset_token.valid?.should be_true # Still valid (not used, not expired)
    end
  end

  describe "multi-organization user workflow" do
    it "user belongs to multiple organizations with different permissions" do
      user = create_user("multi@example.com", "Multi User")

      # Create first org - user is admin
      org1 = App::Models::Organization.new(name: "Org One")
      org1.owner_id = user.id
      org1.save!
      org1.create_admin_group!
      org1.add(user, App::Permissions::Admin)

      # Create second org - user is invited as viewer
      owner2 = create_user("owner2@example.com", "Owner Two")
      org2 = App::Models::Organization.new(name: "Org Two")
      org2.owner_id = owner2.id
      org2.save!
      org2.create_admin_group!
      org2.add(owner2, App::Permissions::Admin)
      org2.add(user, App::Permissions::Viewer)

      # Verify user has different permissions in each org
      user.organizations.map(&.id).to_set.should eq([org1.id, org2.id].to_set)

      org1.user_has_permission?(user, App::Permissions::Admin).should be_true
      org1.user_can_manage_groups?(user).should be_true

      org2.user_has_permission?(user, App::Permissions::Viewer).should be_true
      org2.user_has_permission?(user, App::Permissions::User).should be_false
      org2.user_can_manage_groups?(user).should be_false
    end
  end

  describe "domain management workflow" do
    it "admin adds and manages domains for organization" do
      owner = create_user("domain-owner@example.com", "Domain Owner")

      org = App::Models::Organization.new(name: "Domain Corp", subdomain: "domain-corp")
      org.owner_id = owner.id
      org.save!
      org.create_admin_group!
      org.add(owner, App::Permissions::Admin)

      # Add domains
      domain1 = App::Models::Domain.new(name: "Example Domain", domain: "example.com", organization_id: org.id)
      domain1.save!
      domain1.persisted?.should be_true

      domain2 = App::Models::Domain.new(name: "Example Org", domain: "example.org", organization_id: org.id)
      domain2.save!

      # Verify domains belong to org
      org.domains.map(&.domain).to_set.should eq(["example.com", "example.org"].to_set)

      # Update domain
      domain1.domain = "newexample.com"
      domain1.save!
      domain1.domain.should eq("newexample.com")

      # Delete domain
      domain2.destroy
      org.domains.count.should eq(1)
    end
  end

  describe "complete groups and invites workflow" do
    it "admin creates groups, adds members, sends invites, new user joins via invite" do
      # Setup organization
      admin = create_user("admin@company.com", "Admin User")
      org = App::Models::Organization.new(name: "Tech Company")
      org.owner_id = admin.id
      org.save!
      admin_group = org.create_admin_group!
      org.add(admin, App::Permissions::Admin)

      # Admin creates dev group
      dev_group = App::Models::Group.new(
        name: "Developers",
        description: "Engineering team",
        organization_id: org.id,
        permission: App::Permissions::User
      )
      dev_group.save!

      # Admin creates manager group
      mgr_group = App::Models::Group.new(
        name: "Managers",
        organization_id: org.id,
        permission: App::Permissions::Manager
      )
      mgr_group.save!

      # Add existing org member to dev group
      existing_member = create_user("existing@company.com", "Existing Member")
      org.add(existing_member, App::Permissions::User)
      dev_group.add_user(existing_member)

      dev_group.user_is_member?(existing_member).should be_true
      existing_member.groups_in_organization(org).pluck(:id).should contain(dev_group.id)

      # Send invite to new user for dev group
      invite = dev_group.invite("newdev@external.com", Time.utc + 48.hours)
      invite.persisted?.should be_true
      invite.expired?.should be_false

      # New user signs up and accepts invite
      new_dev = create_user("newdev@external.com", "New Developer")
      invite.accept!(new_dev)

      # Verify new user is in group AND organization
      dev_group.user_is_member?(new_dev).should be_true
      org.users.where(id: new_dev.id).exists?.should be_true

      # Invite should be deleted
      App::Models::GroupInvite.find?(invite.id).should be_nil

      # Promote existing member to manager group (they're now in 2 groups)
      mgr_group.add_user(existing_member)
      existing_member.groups_in_organization(org).pluck(:id).size.should eq(2)

      # Existing member now has Manager permission through group
      org.user_has_permission?(existing_member, App::Permissions::Manager).should be_true
    end
  end

  describe "permission inheritance and hierarchy" do
    it "higher group permission overrides lower direct permission" do
      admin = create_user("admin@perm.com", "Admin")
      user = create_user("user@perm.com", "User")

      org = App::Models::Organization.new(name: "Perm Test Org")
      org.owner_id = admin.id
      org.save!
      org.create_admin_group!
      org.add(admin, App::Permissions::Admin)

      # Add user with Viewer direct permission
      org.add(user, App::Permissions::Viewer)
      org.user_has_permission?(user, App::Permissions::Viewer).should be_true
      org.user_has_permission?(user, App::Permissions::User).should be_false

      # Create Manager group and add user
      mgr_group = App::Models::Group.new(
        name: "Managers",
        organization_id: org.id,
        permission: App::Permissions::Manager
      )
      mgr_group.save!
      mgr_group.add_user(user)

      # User should now have Manager permission (from group)
      org.user_has_permission?(user, App::Permissions::Manager).should be_true
      org.user_has_permission?(user, App::Permissions::User).should be_true
      org.user_has_permission?(user, App::Permissions::Viewer).should be_true

      # But still not Admin
      org.user_has_permission?(user, App::Permissions::Admin).should be_false
    end
  end

  describe "organization deletion cascade" do
    it "deleting organization cleans up all related data" do
      owner = create_user("cascade-owner@example.com", "Cascade Owner")
      member = create_user("cascade-member@example.com", "Cascade Member")

      org = App::Models::Organization.new(name: "To Be Deleted")
      org.owner_id = owner.id
      org.save!
      org_id = org.id

      admin_group = org.create_admin_group!
      org.add(owner, App::Permissions::Admin)
      org.add(member, App::Permissions::User)

      # Create group
      group = App::Models::Group.new(name: "Test Group", organization_id: org.id, permission: App::Permissions::User)
      group.save!
      group.add_user(member)

      # Create domain
      domain = App::Models::Domain.new(name: "To Delete Domain", domain: "todelete.com", organization_id: org.id)
      domain.save!

      # Create pending invite
      invite = org.invite("pending@example.com")

      # Verify everything exists
      App::Models::Organization.find?(org_id).should_not be_nil
      App::Models::Group.where(organization_id: org_id).count.should be > 0
      App::Models::OrganizationUser.where(organization_id: org_id).count.should be > 0

      # Delete organization
      org.destroy

      # Verify cascade deletion
      App::Models::Organization.find?(org_id).should be_nil
      App::Models::Group.where(organization_id: org_id).count.should eq(0)
      App::Models::OrganizationUser.where(organization_id: org_id).count.should eq(0)
      App::Models::Domain.where(organization_id: org_id).count.should eq(0)
      App::Models::OrganizationInvite.where(organization_id: org_id).count.should eq(0)

      # Users should still exist
      App::Models::User.find?(owner.id).should_not be_nil
      App::Models::User.find?(member.id).should_not be_nil
    end
  end
end
