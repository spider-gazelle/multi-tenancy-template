# OAuth Tokens Controller - List and revoke OAuth tokens
#
# Provides API endpoints for managing OAuth tokens.
# Users can view and revoke their own tokens.
# Organization managers can view tokens for their organization's OAuth apps.

class App::OAuthTokens < App::Base
  base "/oauth/tokens"

  # Manage OAuth tokens (view)
  @[AC::Route::GET("/manage")]
  def manage
    render html: File.read("views/oauth_tokens.html")
  end

  # Filters
  ###############################################################################################

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action, only: [:show, :revoke])]
  private def find_token(id : String)
    @current_token = Models::OAuthToken.find!(UUID.new(id))
  end

  getter! current_token : Models::OAuthToken

  @[AC::Route::Filter(:before_action, only: [:show, :revoke])]
  private def require_token_access
    token = current_token
    user = current_user.not_nil!

    # Users can access their own tokens
    return if token.user_id == user.id

    # Admins can access any token
    return if user.sys_admin?

    # Check if user manages the OAuth client's organization
    if client_id = token.client_id
      if client = Models::OAuthClient.find?(UUID.new(client_id))
        if org_id = client.organization_id
          org = Models::Organization.find?(org_id)
          if org && has_permission?(org, Permissions::Manager)
            return
          end
        end
      end
    end

    raise Error::Forbidden.new("Access denied")
  end

  # Routes
  ###############################################################################################

  # List tokens for current user
  @[AC::Route::GET("/")]
  def index(
    @[AC::Param::Info(description: "Filter by client_id")]
    client_id : String? = nil,
    @[AC::Param::Info(description: "Filter by token_type (access_token, refresh_token)")]
    token_type : String? = nil,
    @[AC::Param::Info(description: "Include revoked tokens")]
    include_revoked : Bool = false,
    @[AC::Param::Info(description: "Include expired tokens")]
    include_expired : Bool = false,
  )
    params = search_params
    user = current_user.not_nil!

    query = Models::OAuthToken.where(user_id: user.id)

    # Apply filters
    query = query.where(client_id: client_id) if client_id
    query = query.where(token_type: token_type) if token_type
    query = query.where(raw: "revoked_at IS NULL") unless include_revoked
    query = query.where(raw: "expires_at > now()") unless include_expired

    # Paginate and return results
    paginate_results(query, "oauth_tokens", "/oauth/tokens")
  end

  # List tokens for an OAuth application (organization managers only)
  @[AC::Route::GET("/by-application/:application_id")]
  def by_application(
    application_id : String,
    @[AC::Param::Info(description: "Include revoked tokens")]
    include_revoked : Bool = false,
    @[AC::Param::Info(description: "Include expired tokens")]
    include_expired : Bool = false,
  )
    params = search_params
    user = current_user.not_nil!

    # Find the application and check access
    app = Models::OAuthClient.find!(UUID.new(application_id))

    unless user.sys_admin?
      if org_id = app.organization_id
        org = Models::Organization.find!(org_id)
        require_organization_access!(org)
        require_permission!(org, Permissions::Manager)
      else
        raise Error::Forbidden.new("Access denied")
      end
    end

    query = Models::OAuthToken.where(client_id: application_id)

    # Apply filters
    query = query.where(raw: "revoked_at IS NULL") unless include_revoked
    query = query.where(raw: "expires_at > now()") unless include_expired

    # Paginate and return results
    paginate_results(query, "oauth_tokens", "/oauth/tokens/by-application/#{application_id}")
  end

  # Get token details
  @[AC::Route::GET("/:id")]
  def show : Models::OAuthToken
    current_token
  end

  # Revoke a token
  @[AC::Route::POST("/:id/revoke")]
  def revoke : Models::OAuthToken
    token = current_token

    if token.revoked?
      raise Error::BadRequest.new("Token is already revoked")
    end

    token.revoked_at = Time.utc
    token.save!

    audit_log(Models::AuditLog::Actions::DELETE, Models::AuditLog::Resources::OAUTH_TOKEN, token.id)

    token
  end

  # Revoke all tokens for current user
  @[AC::Route::POST("/revoke-all")]
  def revoke_all(
    @[AC::Param::Info(description: "Only revoke tokens for this client_id")]
    client_id : String? = nil,
  ) : NamedTuple(revoked_count: Int32)
    user = current_user.not_nil!

    query = Models::OAuthToken
      .where(user_id: user.id)
      .where(raw: "revoked_at IS NULL")
      .where(raw: "expires_at > now()")

    query = query.where(client_id: client_id) if client_id

    tokens = query.to_a
    revoked_count = 0

    tokens.each do |token|
      token.revoked_at = Time.utc
      if token.save
        revoked_count += 1
      end
    end

    audit_log(Models::AuditLog::Actions::DELETE, Models::AuditLog::Resources::OAUTH_TOKEN, nil, nil, {
      "revoked_count" => revoked_count.to_s,
      "client_id"     => client_id || "all",
    } of String => JSON::Any::Type)

    {revoked_count: revoked_count}
  end
end
