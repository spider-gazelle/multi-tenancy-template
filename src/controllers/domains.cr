class App::Domains < App::Base
  base "/organizations"

  # Filters
  ###############################################################################################

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action)]
  private def find_organization(id : String)
    @current_org = Models::Organization.find!(UUID.new(id))
  end

  getter! current_org : Models::Organization

  @[AC::Route::Filter(:before_action)]
  private def require_org_access
    require_organization_access!(current_org)
  end

  @[AC::Route::Filter(:before_action, except: [:index, :show])]
  private def require_admin
    require_permission!(current_org, Permissions::Admin)
  end

  @[AC::Route::Filter(:before_action, except: [:index, :create])]
  private def find_domain(domain_id : String)
    @current_domain = Models::Domain.find_by(id: UUID.new(domain_id), organization_id: current_org.id)
  end

  getter! current_domain : Models::Domain

  # Routes
  ###############################################################################################

  # List organization domains
  @[AC::Route::GET("/:id/domains")]
  def index : Array(Models::Domain)
    Models::Domain.where(organization_id: current_org.id).to_a
  end

  # Get domain details
  @[AC::Route::GET("/:id/domains/:domain_id")]
  def show : Models::Domain
    current_domain
  end

  # Create domain
  @[AC::Route::POST("/:id/domains", body: :domain, status_code: HTTP::Status::CREATED)]
  def create(domain : Models::Domain) : Models::Domain
    domain.organization_id = current_org.id
    domain.save!
    domain
  end

  # Update domain
  @[AC::Route::PATCH("/:id/domains/:domain_id", body: :domain)]
  @[AC::Route::PUT("/:id/domains/:domain_id", body: :domain)]
  def update(domain : Models::Domain) : Models::Domain
    current = current_domain
    current.assign_attributes(domain)
    current.organization_id = current_org.id
    raise Error::ModelValidation.new(current.errors) unless current.save
    current
  end

  # Delete domain
  @[AC::Route::DELETE("/:id/domains/:domain_id", status_code: HTTP::Status::ACCEPTED)]
  def destroy : Nil
    current_domain.destroy
  end
end
