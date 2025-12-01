require "uuid"
require "../error"

abstract class App::Base < ActionController::Base
  # Configure your log source name
  # NOTE:: this is chaining from Log
  Log = ::App::Log.for("controller")

  # framework uses "application/json" by default
  add_responder("text/html") { |io, result| result.to_json(io) }

  @current_user : Models::User? = nil
  @current_organization : Models::Organization? = nil

  # Get current user from session
  def current_user : Models::User?
    return @current_user if @current_user

    if user_id_value = session["user_id"]?
      user_id = user_id_value.is_a?(String) ? user_id_value : user_id_value.to_s
      @current_user = Models::User.find?(UUID.new(user_id))
    end

    @current_user
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

    org_user = Models::OrganizationUser.find?({user.id, org.id})
    org_user.try(&.permission)
  end

  # Check if user has at least the specified permission level
  def has_permission?(org : Models::Organization, min_permission : Permissions) : Bool
    permission = user_permission_in_org(org)
    return false unless permission

    # Lower enum value = higher permission (Admin=0, Viewer=3)
    permission.value <= min_permission.value
  end

  # Check if user is authenticated (returns boolean)
  def authenticated? : Bool
    !current_user.nil?
  end

  # Require authentication
  def require_auth!
    raise Error::Unauthorized.new("Authentication required") unless current_user
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
