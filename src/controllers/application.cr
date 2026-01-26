require "uuid"
require "uuid/json"
require "../error"
require "../helpers/pagination"

abstract class App::Base < ActionController::Base
  include Pagination

  # Configure your log source name
  # NOTE:: this is chaining from Log
  Log = ::App::Log.for("controller")

  # framework uses "application/json" by default
  add_responder("text/html") { |io, result| result.to_json(io) }

  @current_user : Models::User? = nil
  @current_organization : Models::Organization? = nil
  @current_api_key : Models::ApiKey? = nil
  @current_jwt_user : Models::User? = nil

  # Get current user from session, API key, or JWT token
  def current_user : Models::User?
    return @current_user if @current_user

    # Try API key first (from Authorization header)
    if api_key = current_api_key
      @current_user = api_key.user
      return @current_user
    end

    # Try JWT token (from Authorization header)
    if jwt_user = current_jwt_user
      @current_user = jwt_user
      return @current_user
    end

    # Fall back to session
    if user_id_value = session["user_id"]?
      user_id = user_id_value.is_a?(String) ? user_id_value : user_id_value.to_s
      @current_user = Models::User.find?(UUID.new(user_id))
    end

    @current_user
  end

  # Get current API key from Authorization header
  def current_api_key : Models::ApiKey?
    return @current_api_key if @current_api_key

    auth_header = request.headers["Authorization"]?
    return nil unless auth_header

    if auth_header.starts_with?("Bearer sk_")
      raw_key = auth_header.sub("Bearer ", "")
      @current_api_key = Models::ApiKey.authenticate(raw_key)
    end

    @current_api_key
  end

  # Get current user from JWT token
  private def current_jwt_user : Models::User?
    return @current_jwt_user if @current_jwt_user

    auth_header = request.headers["Authorization"]?
    return nil unless auth_header
    return nil if auth_header.starts_with?("Bearer sk_")

    token = auth_header.sub(/^Bearer\s+/i, "")
    return nil if token.empty?

    begin
      Log.debug { "Attempting to decode JWT token (length: #{token.size}, dots: #{token.count('.')})" }

      # Decode and verify JWT token
      payload, _ = Authly.jwt_decode(token)

      # Check if token is revoked (using jti claim)
      if jti = payload["jti"]?
        jti_str = jti.as_s? || jti.to_s
        # Check revocation directly in token store, not through Authly.revoked?
        # because Authly.revoked? expects the full JWT token, not the jti
        store = Authly.config.token_store
        if store.is_a?(App::AuthlyTokenStore)
          return nil if store.revoked?(jti_str)
        end
      end

      # Extract user ID from sub claim (already a UUID string)
      sub_claim = payload["sub"]?
      return nil unless sub_claim

      user_id_str = sub_claim.as_s? || sub_claim.to_s
      return nil if user_id_str.empty?

      Log.debug { "JWT decoded successfully, user_id: #{user_id_str}" }

      # Find and return user
      @current_jwt_user = Models::User.find?(UUID.new(user_id_str))
    rescue ex
      Log.warn(exception: ex) { "Error decoding JWT token" }
      nil
    end
  end

  # Get JWT token scopes (if authenticated via JWT)
  # Returns array of scopes from JWT token, or empty array
  def jwt_scopes : Array(String)
    return [] of String unless current_jwt_user

    auth_header = request.headers["Authorization"]?
    return [] of String unless auth_header

    token = auth_header.sub(/^Bearer\s+/i, "")
    return [] of String if token.empty?

    begin
      payload, _ = Authly.jwt_decode(token)

      # Handle scope as array (standard OAuth2 JWT format)
      if scope_claim = payload["scope"]?
        if scope_claim.as_a?
          return scope_claim.as_a.map(&.as_s)
        elsif scope_claim.as_s?
          # Fallback: handle legacy string format
          return scope_claim.as_s.split(" ")
        end
      end
    rescue
      # Ignore errors, return empty array
    end

    [] of String
  end

  # Check if JWT token has a specific scope
  def jwt_has_scope?(scope : String) : Bool
    jwt_scopes.includes?(scope)
  end

  # Check if request is authenticated via API key
  def api_key_auth? : Bool
    !current_api_key.nil?
  end

  # Get current organization from session
  def current_organization : Models::Organization?
    return @current_organization if @current_organization

    if org_id_value = session["organization_id"]?
      org_id = org_id_value.is_a?(String) ? org_id_value : org_id_value.to_s
      @current_organization = Models::Organization.find?(UUID.new(org_id))
    end

    @current_organization
  end

  # Set current organization in session
  def current_organization=(org : Models::Organization)
    session["organization_id"] = org.id.to_s
    @current_organization = org
  end

  # Get user's organizations
  def user_organizations : Array(Models::Organization)
    return [] of Models::Organization unless user = current_user
    user.organizations.to_a
  end

  # Get user's permission in an organization
  def user_permission_in_org(org : Models::Organization) : Permissions?
    return nil unless user = current_user

    # For JWT authentication, check if scopes grant organization-level permissions
    if current_jwt_user && (jwt_permission = jwt_permission_for_org(org))
      return jwt_permission
    end

    # Check direct organization membership first (for backward compatibility)
    org_user = Models::OrganizationUser.find?({user.id, org.id})
    direct_permission = org_user.try(&.permission)

    # Check group-based permissions
    user_groups = Models::Group.join(:inner, Models::GroupUser, :group_id)
      .where("groups.organization_id = ? AND group_users.user_id = ?", org.id, user.id)

    group_permissions = user_groups.map(&.permission)

    # Return the highest permission level (lowest enum value)
    all_permissions = [direct_permission, group_permissions].flatten.compact
    return nil if all_permissions.empty?

    all_permissions.min_by(&.value)
  end

  # Map JWT scopes to organization permissions
  # This allows OAuth2 clients to have scoped access to organizations
  private def jwt_permission_for_org(org : Models::Organization) : Permissions?
    scopes = jwt_scopes
    return nil if scopes.empty?

    # Check for organization-specific scopes first
    # Format: "org:{org_id}:admin", "org:{org_id}:manager", etc.
    org_prefix = "org:#{org.id}:"

    if scopes.any? { |s| s == "#{org_prefix}admin" }
      return Permissions::Admin
    elsif scopes.any? { |s| s == "#{org_prefix}manager" }
      return Permissions::Manager
    elsif scopes.any? { |s| s == "#{org_prefix}user" }
      return Permissions::User
    elsif scopes.any? { |s| s == "#{org_prefix}viewer" }
      return Permissions::Viewer
    end

    # Check for global permission scopes
    # These grant the same permission across all organizations the user has access to
    if scopes.includes?("admin")
      return Permissions::Admin
    elsif scopes.includes?("manager")
      return Permissions::Manager
    elsif scopes.includes?("user")
      return Permissions::User
    elsif scopes.includes?("viewer")
      return Permissions::Viewer
    end

    # Check for resource-specific scopes that imply permissions
    # e.g., "organizations.write" implies Manager, "organizations.read" implies Viewer
    if scopes.includes?("organizations.write") || scopes.includes?("organizations.admin")
      return Permissions::Manager
    elsif scopes.includes?("organizations.read")
      return Permissions::Viewer
    end

    nil
  end

  # Check if user has at least the specified permission level
  def has_permission?(org : Models::Organization, min_permission : Permissions) : Bool
    return org.user_has_permission?(current_user.not_nil!, min_permission) if current_user
    false
  end

  # Check if user is authenticated (returns boolean)
  def authenticated? : Bool
    !current_user.nil?
  end

  # Require authentication
  def require_auth!
    raise Error::Unauthorized.new("Authentication required") unless current_user
  end

  # Require API key with specific scope
  def require_api_key_scope!(scope : String)
    raise Error::Forbidden.new("API key required") unless api_key = current_api_key
    raise Error::Forbidden.new("Insufficient API key scope") unless api_key.has_scope?(scope)
  end

  # Log an audit event
  def audit_log(
    action : String,
    resource_type : String,
    resource_id : UUID? = nil,
    organization : Models::Organization? = nil,
    details : Hash(String, JSON::Any::Type)? = nil,
  )
    Models::AuditLog.log(
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      user: current_user,
      organization: organization,
      details: details,
      ip_address: client_ip,
      user_agent: request.headers["User-Agent"]?
    )
  end

  # Require organization membership
  def require_organization_access!(org : Models::Organization)
    require_auth!
    raise Error::Forbidden.new("Not a member of organization") unless user_permission_in_org(org)
  end

  # Require specific permission level in organization
  def require_permission!(org : Models::Organization, min_permission : Permissions)
    require_organization_access!(org)
    raise Error::Forbidden.new("Insufficient permissions: #{min_permission} required") unless has_permission?(org, min_permission)
  end

  # This makes it simple to match client requests with server side logs.
  # When building microservices this ID should be propagated to upstream services.
  @[AC::Route::Filter(:before_action)]
  def set_request_id
    request_id = UUID.random.to_s
    Log.context.set(
      client_ip: client_ip,
      request_id: request_id
    )
    response.headers["X-Request-ID"] = request_id

    # If this is an upstream service, the ID should be extracted from a request header.
    # request_id = request.headers["X-Request-ID"]? || UUID.random.to_s
    # Log.context.set client_ip: client_ip, request_id: request_id
    # response.headers["X-Request-ID"] = request_id
  end

  @[AC::Route::Filter(:before_action)]
  def set_date_header
    response.headers["Date"] = HTTP.format_time(Time.utc)
  end

  getter! search_params : Hash(String, String | UInt32 | Array(String))

  @[AC::Route::Filter(:before_action, only: [:index, :by_application], converters: {fields: ConvertStringArray})]
  def build_search_params(
    @[AC::Param::Info(name: "q", description: "Search query for full-text search")]
    query : String = "*",
    @[AC::Param::Info(description: "Maximum number of results to return")]
    limit : UInt32 = DEFAULT_LIMIT,
    @[AC::Param::Info(description: "Starting offset for pagination")]
    offset : UInt32 = 0_u32,
    @[AC::Param::Info(description: "Field to sort by")]
    sort : String = "name",
    @[AC::Param::Info(description: "Sort order (asc or desc)")]
    order : String = "asc",
    @[AC::Param::Info(description: "a token for accessing the next page of results, provided in the `Link` header")]
    ref : String? = nil,
    @[AC::Param::Info(description: "Comma-separated fields to search")]
    fields : Array(String) = [] of String,
  )
    limit = MAX_LIMIT if limit > MAX_LIMIT
    limit = 1_u32 if limit < 1

    search_params = {
      "q"      => query,
      "limit"  => limit,
      "offset" => offset,
      "sort"   => sort,
      "order"  => order,
      "fields" => fields,
    }
    search_params["ref"] = ref.not_nil! if ref.presence
    @search_params = search_params
  end

  # ========================
  # Action Controller Errors
  # ========================

  # covers no acceptable response format and not an acceptable post format
  @[AC::Route::Exception(AC::Route::NotAcceptable, status_code: HTTP::Status::NOT_ACCEPTABLE)]
  @[AC::Route::Exception(AC::Route::UnsupportedMediaType, status_code: HTTP::Status::UNSUPPORTED_MEDIA_TYPE)]
  def bad_media_type(error) : AC::Error::ContentResponse
    AC::Error::ContentResponse.new error: error.message.as(String), accepts: error.accepts
  end

  # handles paramater missing or a bad paramater value / format
  @[AC::Route::Exception(AC::Route::Param::MissingError, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
  @[AC::Route::Exception(AC::Route::Param::ValueError, status_code: HTTP::Status::BAD_REQUEST)]
  def invalid_param(error) : AC::Error::ParameterResponse
    AC::Error::ParameterResponse.new error: error.message.as(String), parameter: error.parameter, restriction: error.restriction
  end

  # 401 if no bearer token
  @[AC::Route::Exception(Error::Unauthorized, status_code: HTTP::Status::UNAUTHORIZED)]
  def resource_requires_authentication(error) : CommonError
    Log.debug { error.message }
    CommonError.new(error, false)
  end

  # 403 if user role invalid for a route
  @[AC::Route::Exception(Error::Forbidden, status_code: HTTP::Status::FORBIDDEN)]
  def resource_access_forbidden(error) : Nil
    Log.debug { error.inspect_with_backtrace }
  end

  # 400 if bad request
  @[AC::Route::Exception(Error::BadRequest, status_code: HTTP::Status::BAD_REQUEST)]
  def bad_request(error) : CommonError
    Log.debug { error.message }
    CommonError.new(error, false)
  end

  # 404 if resource not present
  @[AC::Route::Exception(Error::NotFound, status_code: HTTP::Status::NOT_FOUND)]
  @[AC::Route::Exception(PgORM::Error::RecordNotFound, status_code: HTTP::Status::NOT_FOUND)]
  def resource_not_found(error) : CommonError
    Log.debug(exception: error) { error.message }
    CommonError.new(error, false)
  end

  ###########################################################################
  # Error Handlers
  ###########################################################################

  struct CommonError
    include JSON::Serializable

    getter error : String?
    getter backtrace : Array(String)?

    def initialize(error, backtrace = true)
      @error = error.message
      @backtrace = backtrace ? error.backtrace : nil
    end
  end

  # ========================
  # Model Validation Errors
  # ========================

  struct ValidationError
    include JSON::Serializable
    include YAML::Serializable

    getter error : String
    getter failures : Array(NamedTuple(field: Symbol, reason: String))

    def initialize(@error, @failures)
    end
  end

  # handles model validation errors
  @[AC::Route::Exception(Error::ModelValidation, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
  def model_validation(error) : ValidationError
    ValidationError.new error.message.not_nil!, error.failures
  end
end
