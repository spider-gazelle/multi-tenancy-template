class App::Profile < App::Base
  base "/profile"

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  # Show profile page
  @[AC::Route::GET("/")]
  def show
    user = current_user.not_nil!
    html = File.read("views/profile.html")
    html = html.gsub("{{USER_NAME}}", HTML.escape(user.name))
    html = html.gsub("{{USER_EMAIL}}", HTML.escape(user.email))

    # Check if user has password (vs OAuth-only)
    has_password = !user.password_hash.nil? && !user.password_hash.try(&.empty?)
    html = html.gsub("{{HAS_PASSWORD}}", has_password.to_s)

    # Get linked OAuth providers
    auth_sources = Models::Auth.where(user_id: user.id).to_a
    providers = auth_sources.map(&.provider).uniq
    html = html.gsub("{{OAUTH_PROVIDERS}}", providers.map(&.capitalize).join(", "))
    html = html.gsub("{{HAS_OAUTH}}", (!providers.empty?).to_s)

    render html: html
  end

  # Update profile name
  @[AC::Route::POST("/update")]
  def update(
    @[AC::Param::Info(description: "User name")]
    name : String,
  )
    user = current_user.not_nil!

    if name.strip.empty?
      redirect_to "/profile?error=Name+cannot+be+empty", status: :see_other
      return
    end

    user.name = name.strip
    user.save!

    # Update session
    session["user_name"] = user.name

    redirect_to "/profile?success=Profile+updated", status: :see_other
  end

  # Change password
  @[AC::Route::POST("/change-password")]
  def change_password(
    @[AC::Param::Info(description: "Current password")]
    current_password : String,
    @[AC::Param::Info(description: "New password")]
    new_password : String,
    @[AC::Param::Info(description: "Confirm new password")]
    confirm_password : String,
  )
    user = current_user.not_nil!

    # Verify current password if user has one
    if user.password_hash && !user.password_hash.try(&.empty?)
      unless user.verify_password(current_password)
        redirect_to "/profile?error=Current+password+is+incorrect", status: :see_other
        return
      end
    end

    # Validate new password
    if new_password.size < 8
      redirect_to "/profile?error=Password+must+be+at+least+8+characters", status: :see_other
      return
    end

    if new_password != confirm_password
      redirect_to "/profile?error=Passwords+do+not+match", status: :see_other
      return
    end

    user.password = new_password
    user.save!

    redirect_to "/profile?success=Password+changed", status: :see_other
  end

  # List API keys
  @[AC::Route::GET("/api-keys")]
  def list_api_keys : Array(NamedTuple(id: String, name: String, key_prefix: String, scopes: Array(String), expires_at: String?, last_used_at: String?, created_at: String))
    user = current_user.not_nil!
    keys = Models::ApiKey.where(user_id: user.id).to_a

    keys.map do |key|
      {
        id:           key.id.to_s,
        name:         key.name,
        key_prefix:   key.key_prefix,
        scopes:       key.scopes,
        expires_at:   key.expires_at.try(&.to_s("%Y-%m-%d")),
        last_used_at: key.last_used_at.try(&.to_s("%Y-%m-%d %H:%M")),
        created_at:   key.created_at.to_s("%Y-%m-%d"),
      }
    end
  end

  # Create API key
  @[AC::Route::POST("/api-keys")]
  def create_api_key : NamedTuple(id: String, name: String, key: String, key_prefix: String)
    user = current_user.not_nil!

    name = params["name"]?.try(&.to_s) || "API Key"
    scopes = params["scopes"]?.try(&.to_s.split(",").map(&.strip).reject(&.empty?)) || [] of String

    expires_at : Time? = nil
    if exp = params["expires_in_days"]?.try(&.to_s.to_i?)
      expires_at = Time.utc + exp.days if exp > 0
    end

    api_key, raw_key = Models::ApiKey.create_for_user(user, name, scopes, expires_at)

    {
      id:         api_key.id.to_s,
      name:       api_key.name,
      key:        raw_key,
      key_prefix: api_key.key_prefix,
    }
  end

  # Delete API key
  @[AC::Route::DELETE("/api-keys/:key_id")]
  def delete_api_key(key_id : String) : NamedTuple(success: Bool)
    user = current_user.not_nil!

    key = Models::ApiKey.find?(UUID.new(key_id))
    if key && key.user_id == user.id
      key.destroy
      {success: true}
    else
      {success: false}
    end
  end
end
