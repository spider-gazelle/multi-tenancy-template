require "email"
require "ecr"

module App::Services
  class EmailService
    Log = ::Log.for(self)

    @@config : EMail::Client::Config?

    def self.configure
      # Only configure if SMTP settings are present
      return unless ENV["SMTP_HOST"]?

      # Determine TLS mode from environment variable
      tls_mode = case ENV["SMTP_TLS"]?.try(&.downcase)
                 when "none", "false", "0"
                   EMail::Client::TLSMode::NONE
                 when "smtps", "ssl"
                   EMail::Client::TLSMode::SMTPS
                 else
                   EMail::Client::TLSMode::STARTTLS
                 end

      # Only use auth if TLS is enabled (required by most SMTP servers)
      auth = tls_mode == EMail::Client::TLSMode::NONE ? nil : {ENV["SMTP_USERNAME"], ENV["SMTP_PASSWORD"]}

      @@config = EMail::Client::Config.create(
        ENV["SMTP_HOST"],
        ENV["SMTP_PORT"].to_i,
        helo_domain: ENV["SMTP_FROM_EMAIL"].split("@").last,
        use_tls: tls_mode,
        auth: auth
      )
    rescue ex
      Log.warn(exception: ex) { "Failed to configure email service - email features will be disabled" }
    end

    def self.config : EMail::Client::Config
      @@config || raise "EmailService not configured. Set SMTP_* environment variables to enable email features."
    end

    def self.configured? : Bool
      !@@config.nil?
    end

    def self.send_organization_invite(invite : Models::OrganizationInvite, inviter : Models::User)
      unless configured?
        Log.warn { "Email service not configured - skipping organization invite email to #{invite.email}" }
        return
      end

      organization = invite.organization
      invite_url = "#{ENV["APP_BASE_URL"]}/organizations/invites/#{invite.id}/accept?secret=#{invite.secret}"

      # Template variables
      inviter_name = inviter.name
      org_name = organization.name
      org_description = organization.description
      permission = invite.permission.to_s
      expires = invite.expires

      body = ECR.render("views/emails/organization_invite.ecr")

      email = EMail::Message.new
      email.from ENV["SMTP_FROM_EMAIL"], ENV["SMTP_FROM_NAME"]
      email.to invite.email
      email.subject "You've been invited to join #{organization.name}"
      email.message_html body

      client = EMail::Client.new(config)
      client.start do
        send(email)
      end

      Log.info { "Organization invite email sent to #{invite.email} for organization #{organization.name}" }
    rescue ex
      Log.error(exception: ex) { "Failed to send organization invite email to #{invite.email}" }
      raise ex
    end

    def self.send_password_reset(user : Models::User, token : String)
      unless configured?
        Log.warn { "Email service not configured - skipping password reset email to #{user.email}" }
        return
      end

      reset_url = "#{ENV["APP_BASE_URL"]}/auth/reset-password?token=#{token}"

      # Template variables
      user_name = user.name

      body = ECR.render("views/emails/password_reset.ecr")

      email = EMail::Message.new
      email.from ENV["SMTP_FROM_EMAIL"], ENV["SMTP_FROM_NAME"]
      email.to user.email
      email.subject "Password Reset Request"
      email.message_html body

      client = EMail::Client.new(config)
      client.start do
        send(email)
      end

      Log.info { "Password reset email sent to #{user.email}" }
    rescue ex
      Log.error(exception: ex) { "Failed to send password reset email to #{user.email}" }
      raise ex
    end

    def self.send_group_invite(invite : Models::GroupInvite, inviter : Models::User)
      unless configured?
        Log.warn { "Email service not configured - skipping group invite email to #{invite.email}" }
        return
      end

      group = invite.group
      organization = group.organization
      invite_url = "#{ENV["APP_BASE_URL"]}/groups/invites/#{invite.id}/accept?secret=#{invite.secret}"

      # Template variables
      inviter_name = inviter.name
      group_name = group.name
      group_description = group.description
      org_name = organization.name
      permission = group.permission.to_s
      expires = invite.expires

      body = ECR.render("views/emails/group_invite.ecr")

      email = EMail::Message.new
      email.from ENV["SMTP_FROM_EMAIL"], ENV["SMTP_FROM_NAME"]
      email.to invite.email
      email.subject "You've been invited to join #{group_name} in #{organization.name}"
      email.message_html body

      client = EMail::Client.new(config)
      client.start do
        send(email)
      end

      Log.info { "Group invite email sent to #{invite.email} for group #{group.name}" }
    rescue ex
      Log.error(exception: ex) { "Failed to send group invite email to #{invite.email}" }
      raise ex
    end
  end
end
