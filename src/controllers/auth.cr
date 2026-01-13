require "multi_auth"
require "multi_auth/providers/generic_oauth2"

class App::Auth < App::Base
  base "/auth"

  # Configure OAuth providers
  MultiAuth.config("google", ENV["GOOGLE_CLIENT_ID"]? || "", ENV["GOOGLE_CLIENT_SECRET"]? || "")

  # Configure Microsoft using GenericOAuth2
  MultiAuth.config("microsoft") do |redirect_uri, _provider_id|
    # Use tenant ID if provided, otherwise use 'common' for multi-tenant
    # Set MICROSOFT_TENANT_ID to your tenant ID for single-tenant apps
    # Use 'common' for multi-tenant (personal + work accounts)
    # Use 'organizations' for work/school accounts only
    # Use 'consumers' for personal Microsoft accounts only
    tenant = ENV["MICROSOFT_TENANT_ID"]? || "common"

    MultiAuth::Provider::GenericOAuth2.new(
      provider_name: "microsoft",
      redirect_uri: redirect_uri,
      key: ENV["MICROSOFT_CLIENT_ID"]? || "",
      secret: ENV["MICROSOFT_CLIENT_SECRET"]? || "",
      site: "https://login.microsoftonline.com",
      authorize_url: "/#{tenant}/oauth2/v2.0/authorize",
      token_url: "/#{tenant}/oauth2/v2.0/token",
      authentication_scheme: "request_body",
      user_profile_url: "https://graph.microsoft.com/v1.0/me",
      scopes: "openid profile email User.Read",
      info_mappings: {
        "uid"        => "id",
        "email"      => "userPrincipalName", # Use userPrincipalName as it works for both personal and work accounts
        "name"       => "displayName",
        "first_name" => "givenName",
        "last_name"  => "surname",
      }
    )
  end

  # Show login page
  @[AC::Route::GET("/login")]
  def login
    error = params["error"]?.try(&.to_s)
    html = File.read("views/login.html")

    # Inject error message if present
    if error
      error_html = %(<div class="error">#{HTML.escape(error)}</div>)
      html = html.sub("<div id=\"error-message\"></div>", error_html)
    else
      html = html.sub("<div id=\"error-message\"></div>", "")
    end

    render html: html
  end

  # Handle username/password login
  @[AC::Route::POST("/login")]
  def login_post(
    @[AC::Param::Info(description: "User email", example: "user@example.com")]
    email : String,
    @[AC::Param::Info(description: "User password")]
    password : String,
  )
    user = Models::User.where(email: email.strip.downcase).first?

    location = if user && user.verify_password(password)
                 session["user_id"] = user.id.to_s
                 session["user_name"] = user.name
                 audit_log(Models::AuditLog::Actions::LOGIN, Models::AuditLog::Resources::USER, user.id)
                 "/"
               else
                 "/auth/login?error=Invalid+email+or+password"
               end
    redirect_to location, status: :see_other
  end

  # Initiate OAuth flow
  @[AC::Route::GET("/oauth/:provider")]
  def oauth_initiate(
    @[AC::Param::Info(description: "OAuth provider (google or microsoft)")]
    provider : String,
  )
    scheme = request.headers["X-Forwarded-Proto"]? || "http"
    host = request.headers["Host"]? || "localhost:3000"
    redirect_uri = "#{scheme}://#{host}/auth/oauth/#{provider}/callback"
    multi_auth = MultiAuth.make(provider, redirect_uri)

    redirect_to multi_auth.authorize_uri(scope: oauth_scope(provider)), status: :see_other
  end

  # OAuth callback handler
  @[AC::Route::GET("/oauth/:provider/callback")]
  def oauth_callback(
    @[AC::Param::Info(description: "OAuth provider (google or microsoft)")]
    provider : String,
  ) : String?
    scheme = request.headers["X-Forwarded-Proto"]? || "http"
    host = request.headers["Host"]? || "localhost:3000"
    redirect_uri = "#{scheme}://#{host}/auth/oauth/#{provider}/callback"
    multi_auth = MultiAuth.make(provider, redirect_uri)

    # Get user info from OAuth provider
    oauth_user = multi_auth.user(request.query_params)

    # Debug: Log what we got from the provider
    Log.info { "OAuth User - Provider: #{oauth_user.provider}, UID: #{oauth_user.uid}, Email: #{oauth_user.email.inspect}, Name: #{oauth_user.name.inspect}" }
    Log.debug { "OAuth Raw JSON: #{oauth_user.raw_json}" }

    # Microsoft fallback: Try multiple email fields if email is nil
    if provider == "microsoft" && oauth_user.email.nil?
      begin
        json = JSON.parse(oauth_user.raw_json)
        # Try in order: mail, userPrincipalName, preferred_username
        oauth_user.email = json["mail"]?.try(&.as_s?) ||
                           json["userPrincipalName"]?.try(&.as_s?) ||
                           json["preferred_username"]?.try(&.as_s?)
        Log.info { "Microsoft email fallback: #{oauth_user.email.inspect}" }
      rescue ex
        Log.warn(exception: ex) { "Failed to parse Microsoft user JSON" }
      end
    end

    # Find or create user
    user = find_or_create_user(oauth_user)

    # Create session
    session["user_id"] = user.id.to_s
    session["user_name"] = user.name
    session["auth_provider"] = provider # Track which provider was used

    redirect_to "/", status: :see_other
  rescue ex
    Log.error(exception: ex) { "OAuth callback error" }
    render status: 500, text: "Authentication failed: #{ex.message}"
  end

  # Logout
  @[AC::Route::GET("/logout")]
  def logout(
    @[AC::Param::Info(description: "Also logout from OAuth provider")]
    provider : String? = nil,
  )
    if user = current_user
      audit_log(Models::AuditLog::Actions::LOGOUT, Models::AuditLog::Resources::USER, user.id)
    end
    session.delete("user_id")
    session.delete("user_name")
    session.delete("auth_provider")

    # If provider is specified, redirect to their logout endpoint
    if provider
      case provider
      when "microsoft"
        # Microsoft logout - also logs out of Microsoft account
        redirect_to "https://login.microsoftonline.com/common/oauth2/v2.0/logout?post_logout_redirect_uri=#{logout_redirect_uri}", status: :see_other
      when "google"
        # Google logout - also logs out of Google account
        redirect_to "https://accounts.google.com/Logout?continue=#{logout_redirect_uri}", status: :see_other
      else
        redirect_to "/auth/login", status: :see_other
      end
    else
      redirect_to "/auth/login", status: :see_other
    end
  end

  # Show forgot password page
  @[AC::Route::GET("/forgot-password")]
  def forgot_password
    html = File.read("views/forgot_password.html")
    render html: html
  end

  # Handle forgot password request
  @[AC::Route::POST("/forgot-password")]
  def forgot_password_post(
    @[AC::Param::Info(description: "User email", example: "user@example.com")]
    email : String,
  )
    user = Models::User.where(email: email.strip.downcase).first?

    if user
      # Create password reset token
      reset_token, token_string = Models::PasswordResetToken.create_for_user(user)

      # Send email
      begin
        Services::EmailService.send_password_reset(user, token_string)
      rescue ex
        Log.error(exception: ex) { "Failed to send password reset email" }
        redirect_to "/auth/forgot-password?error=Failed+to+send+email", status: :see_other
        return
      end
    end

    # Always show success message (security: don't reveal if email exists)
    redirect_to "/auth/forgot-password?success=true", status: :see_other
  end

  # Show reset password page
  @[AC::Route::GET("/reset-password")]
  def reset_password(
    @[AC::Param::Info(description: "Password reset token")]
    token : String,
  )
    # Verify token exists and is valid
    reset_token = Models::PasswordResetToken.find_by_token(token)

    if reset_token.nil? || !reset_token.valid?
      html = File.read("views/reset_password.html")
      error_html = %(<div class="error">Invalid or expired reset link</div>)
      html = html.sub("<div id=\"error-message\"></div>", error_html)
      render html: html
      return
    end

    html = File.read("views/reset_password.html")
    html = html.sub("{{TOKEN}}", HTML.escape(token))
    render html: html
  end

  # Handle password reset
  @[AC::Route::POST("/reset-password")]
  def reset_password_post(
    @[AC::Param::Info(description: "Password reset token")]
    token : String,
    @[AC::Param::Info(description: "New password")]
    password : String,
    @[AC::Param::Info(description: "Password confirmation")]
    password_confirmation : String,
  )
    # Validate passwords match
    if password != password_confirmation
      redirect_to "/auth/reset-password?token=#{token}&error=Passwords+do+not+match", status: :see_other
      return
    end

    # Validate password length
    if password.size < 8
      redirect_to "/auth/reset-password?token=#{token}&error=Password+must+be+at+least+8+characters", status: :see_other
      return
    end

    # Find and validate token
    reset_token = Models::PasswordResetToken.find_by_token(token)

    if reset_token.nil? || !reset_token.valid?
      redirect_to "/auth/reset-password?token=#{token}&error=Invalid+or+expired+reset+link", status: :see_other
      return
    end

    # Update user password
    user = reset_token.user
    user.password = password
    user.save!

    # Mark token as used
    reset_token.mark_as_used!

    # Log the user in
    session["user_id"] = user.id.to_s
    session["user_name"] = user.name

    redirect_to "/?message=Password+reset+successful", status: :see_other
  end

  private def logout_redirect_uri
    scheme = request.headers["X-Forwarded-Proto"]? || "http"
    host = request.headers["Host"]? || "localhost:3000"
    URI.encode_www_form("#{scheme}://#{host}/auth/login")
  end

  private def oauth_scope(provider : String) : String
    case provider
    when "google"
      "openid profile email"
    when "microsoft"
      "openid profile email User.Read"
    else
      "email"
    end
  end

  private def find_or_create_user(oauth_user : MultiAuth::User) : Models::User
    # Try to find existing auth record
    if auth = Models::Auth.where(provider: oauth_user.provider, uid: oauth_user.uid).first?
      user = auth.user

      # Update user info from OAuth if email is missing or changed
      if email = oauth_user.email
        if user.email.empty? || user.email != email
          user.email = email
          user.save!
        end
      end

      # Update OAuth tokens on each login
      store_oauth_tokens(auth, oauth_user)
      auth.save!

      return user
    end

    # Try to find user by email
    email = oauth_user.email
    user = if email
             Models::User.where(email: email.strip.downcase).first?
           else
             nil
           end

    # Create new user if not found
    unless user
      user = Models::User.new(
        name: oauth_user.name || oauth_user.email || "User",
        email: email || "#{oauth_user.uid}@#{oauth_user.provider}.local"
      )
      user.save!
    end

    # Create auth record with tokens
    auth = Models::Auth.new(
      provider: oauth_user.provider,
      uid: oauth_user.uid,
      user_id: user.id
    )

    # Store OAuth tokens if available
    store_oauth_tokens(auth, oauth_user)
    auth.save!

    user
  end

  # Store OAuth tokens from the provider response
  private def store_oauth_tokens(auth : Models::Auth, oauth_user : MultiAuth::User)
    token = oauth_user.access_token

    # Extract token details based on token type
    case token
    when OAuth2::AccessToken
      auth.access_token = token.access_token
      auth.refresh_token = token.refresh_token
      auth.token_type = token.token_type || "Bearer"

      # Calculate expiration time if expires_in is provided
      if expires_in = token.expires_in
        auth.token_expires_at = Time.utc + expires_in.seconds
      end

      # Store scope if available
      auth.token_scope = token.scope
    when OAuth::AccessToken
      # OAuth 1.0 tokens (less common, but supported)
      auth.access_token = token.token
      auth.refresh_token = token.secret
      auth.token_type = "OAuth"
    end
  end
end
