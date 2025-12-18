require "../spec_helper"

describe App::Services::EmailService do
  describe "password reset email template" do
    it "renders with user name and reset URL" do
      user_name = "John Doe"
      reset_url = "http://localhost:3000/auth/reset-password?token=abc123"

      body = ECR.render("views/emails/password_reset.ecr")

      body.should contain(user_name)
      body.should contain(reset_url)
      body.should contain("Password Reset Request")
      body.should contain("This link will expire in 1 hour")
      # Verify it's in the right context
      body.should contain("Hello John Doe,")
      body.should contain("href=\"http://localhost:3000/auth/reset-password?token=abc123\"")
    end

    it "escapes HTML in user name" do
      user_name = "<script>alert('xss')</script>"
      reset_url = "http://localhost:3000/auth/reset-password?token=abc123"

      body = ECR.render("views/emails/password_reset.ecr")

      body.should_not contain("<script>")
      body.should contain("&lt;script&gt;")
    end

    it "includes proper email styling" do
      user_name = "Test User"
      reset_url = "http://localhost:3000/auth/reset-password?token=abc123"

      body = ECR.render("views/emails/password_reset.ecr")

      body.should contain("font-family: Arial")
      body.should contain("background-color: #3498db")
      body.should contain("Reset Password")
    end
  end

  describe "organization invite email template" do
    it "renders with all required fields" do
      inviter_name = "Jane Smith"
      org_name = "Acme Corp"
      org_description = "A great company"
      permission = "Manager"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = nil

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should contain(inviter_name)
      body.should contain(org_name)
      body.should contain(org_description)
      body.should contain(permission)
      body.should contain(invite_url)
      body.should contain("Organization Invitation")
      # Verify it's in the right context
      body.should contain("Jane Smith has invited you to join <strong>Acme Corp</strong>")
      body.should contain("You've been invited with <strong>Manager</strong> permissions")
      body.should contain("href=\"http://localhost:3000/organizations/invites/123/accept?secret=xyz\"")
    end

    it "renders without optional description" do
      inviter_name = "Jane Smith"
      org_name = "Acme Corp"
      org_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = nil

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should contain(inviter_name)
      body.should contain(org_name)
      body.should contain(permission)
      body.should_not contain("font-style: italic")
    end

    it "renders with expiration date" do
      inviter_name = "Jane Smith"
      org_name = "Acme Corp"
      org_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = Time.utc(2024, 12, 31, 23, 59, 59)

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should contain("December 31, 2024")
      body.should contain("expire")
    end

    it "renders without expiration date" do
      inviter_name = "Jane Smith"
      org_name = "Acme Corp"
      org_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = nil

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should_not contain("expire")
    end

    it "escapes HTML in organization name and description" do
      inviter_name = "Jane"
      org_name = "<script>alert('xss')</script>"
      org_description = "<img src=x onerror=alert(1)>"
      permission = "User"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = nil

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should_not contain("<script>")
      body.should_not contain("<img src=x")
      body.should contain("&lt;script&gt;")
      body.should contain("&lt;img")
    end

    it "includes proper email styling" do
      inviter_name = "Jane"
      org_name = "Test Org"
      org_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
      expires = nil

      body = ECR.render("views/emails/organization_invite.ecr")

      body.should contain("font-family: Arial")
      body.should contain("background-color: #27ae60")
      body.should contain("Accept Invitation")
    end

    it "renders all permission levels correctly" do
      ["Admin", "Manager", "User", "Viewer"].each do |perm|
        inviter_name = "Jane"
        org_name = "Test Org"
        org_description = nil
        permission = perm
        invite_url = "http://localhost:3000/organizations/invites/123/accept?secret=xyz"
        expires = nil

        body = ECR.render("views/emails/organization_invite.ecr")

        body.should contain(perm)
      end
    end
  end

  describe "group invite email template" do
    it "renders with all required fields" do
      inviter_name = "Jane Smith"
      group_name = "Developers"
      org_name = "Acme Corp"
      group_description = "Development team"
      permission = "Manager"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = nil
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should contain(inviter_name)
      body.should contain(group_name)
      body.should contain(org_name)
      body.should contain(group_description)
      body.should contain(permission)
      body.should contain(invite_url)
      body.should contain("Group Invitation")
      body.should contain("Jane Smith")
      body.should contain("Developers")
      body.should contain("Acme Corp")
    end

    it "renders without optional description" do
      inviter_name = "Jane Smith"
      group_name = "Developers"
      org_name = "Acme Corp"
      group_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = nil
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should contain(group_name)
      body.should_not contain("Description:")
    end

    it "renders with expiration date" do
      inviter_name = "Jane Smith"
      group_name = "Developers"
      org_name = "Acme Corp"
      group_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = Time.utc(2024, 12, 31, 23, 59, 59)
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should contain("December 31, 2024")
      body.should contain("expire")
    end

    it "renders without expiration date" do
      inviter_name = "Jane Smith"
      group_name = "Developers"
      org_name = "Acme Corp"
      group_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = nil
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should_not contain("expire")
    end

    it "escapes HTML in group name and description" do
      inviter_name = "Jane"
      group_name = "<script>alert('xss')</script>"
      org_name = "Test Org"
      group_description = "<img src=x onerror=alert(1)>"
      permission = "User"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = nil
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should_not contain("<script>")
      body.should_not contain("<img src=x")
      body.should contain("&lt;script&gt;")
      body.should contain("&lt;img")
    end

    it "includes proper email styling" do
      inviter_name = "Jane"
      group_name = "Test Group"
      org_name = "Test Org"
      group_description = nil
      permission = "User"
      invite_url = "http://localhost:3000/group-invites/123/accept?secret=xyz"
      expires = nil
      invite = MockGroupInvite.new("newdev@example.com")

      body = ECR.render("views/emails/group_invite.ecr")

      body.should contain("font-family: Arial")
      body.should contain("Accept Invitation")
    end
  end
end

# Mock class for group invite email tests
class MockGroupInvite
  getter email : String

  def initialize(@email)
  end
end
