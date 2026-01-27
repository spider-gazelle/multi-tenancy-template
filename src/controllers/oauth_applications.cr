class App::OAuthApplications < App::Base
  base "/oauth/applications"

  # Manage OAuth applications (view)
  @[AC::Route::GET("/manage")]
  def manage
    render html: File.read("views/oauth_applications.html")
  end

  # Filters
  ###############################################################################################

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action, only: [:show, :update, :destroy, :regenerate_secret])]
  private def find_application(id : String)
    @current_app = Models::OAuthClient.find!(UUID.new(id))
  end

  getter! current_app : Models::OAuthClient

  @[AC::Route::Filter(:before_action, only: [:show, :update, :destroy, :regenerate_secret])]
  private def require_app_access
    # Ensure user has access to the application's organization
    if org_id = current_app.organization_id
      org = Models::Organization.find!(org_id)
      require_organization_access!(org)
      require_permission!(org, Permissions::Manager)
      @current_org = org
    else
      # For apps without organization, only system admins can access
      raise Error::Forbidden.new("Access denied") unless current_user.try(&.sys_admin?)
    end
  end

  getter current_org : Models::Organization?

  # Routes
  ###############################################################################################

  # List OAuth applications for current user's organizations
  @[AC::Route::GET("/")]
  def index
    params = search_params
    user = current_user.not_nil!

    # Get applications from user's organizations
    org_ids = user.organizations.map(&.id)

    query = if user.sys_admin?
              # Admins can see all applications
              Models::OAuthClient.all
            elsif org_ids.empty?
              Models::OAuthClient.where("1=0") # Empty result
            else
              Models::OAuthClient.where("organization_id IN (?)", org_ids)
            end

    # Apply search
    query = apply_search(query, params["q"].as(String), params["fields"].as(Array(String)))

    # Apply sorting
    query = apply_sort(query, params["sort"].as(String), params["order"].as(String))

    # Paginate and return results
    paginate_results(query, "oauth_applications", "/oauth/applications")
  end

  # Get application details
  @[AC::Route::GET("/:id")]
  def show : Models::OAuthClient
    current_app
  end

  # Create new OAuth application
  @[AC::Route::POST("/", body: :app, status_code: HTTP::Status::CREATED)]
  def create(app : Models::OAuthClient) : ClientWithSecret
    user = current_user.not_nil!

    # Validate organization access if provided
    if org_id = app.organization_id
      org = Models::Organization.find!(org_id)
      require_organization_access!(org)
      require_permission!(org, Permissions::Manager)
    elsif !user.sys_admin?
      raise Error::BadRequest.new("organization_id is required for non-admin users")
    end

    # Generate client secret
    client_secret = Random::Secure.urlsafe_base64(32)
    app.secret = client_secret
    app.save!

    # Log the action
    audit_log(Models::AuditLog::Actions::CREATE, Models::AuditLog::Resources::OAUTH_APPLICATION, app.id)

    # Return with secret (only time it's visible)
    ClientWithSecret.new(app, client_secret)
  end

  # Update OAuth application
  @[AC::Route::PATCH("/:id", body: :app)]
  @[AC::Route::PUT("/:id", body: :app)]
  def update(app : Models::OAuthClient) : Models::OAuthClient
    current = current_app
    current.assign_attributes(app)
    raise Error::ModelValidation.new(current.errors) unless current.save

    audit_log(Models::AuditLog::Actions::UPDATE, Models::AuditLog::Resources::OAUTH_APPLICATION, UUID.new(current.id))

    current
  end

  # Regenerate client secret
  @[AC::Route::POST("/:id/regenerate-secret")]
  def regenerate_secret : ClientWithSecret
    app = current_app
    client_secret = Random::Secure.urlsafe_base64(32)
    app.secret = client_secret
    app.save!

    audit_log(Models::AuditLog::Actions::UPDATE, Models::AuditLog::Resources::OAUTH_APPLICATION, UUID.new(app.id))

    ClientWithSecret.new(app, client_secret)
  end

  # Delete OAuth application
  @[AC::Route::DELETE("/:id", status_code: HTTP::Status::ACCEPTED)]
  def destroy : Nil
    app_id = current_app.id
    current_app.destroy
    audit_log(Models::AuditLog::Actions::DELETE, Models::AuditLog::Resources::OAUTH_APPLICATION, app_id)
  end

  # Response class for returning client with secret (only used once at creation/regeneration)
  struct ClientWithSecret
    include JSON::Serializable

    getter id : UUID
    getter name : String
    getter client_secret : String
    getter redirect_uris : Array(String)
    getter scopes : Array(String)
    getter grant_types : Array(String)
    getter organization_id : UUID?
    getter active : Bool
    getter created_at : Time
    getter updated_at : Time

    def initialize(app : Models::OAuthClient, @client_secret : String)
      @id = app.id
      @name = app.name
      @redirect_uris = app.redirect_uris
      @scopes = app.scopes
      @grant_types = app.grant_types
      @organization_id = app.organization_id
      @active = app.active
      @created_at = app.created_at.not_nil!
      @updated_at = app.updated_at.not_nil!
    end
  end
end
