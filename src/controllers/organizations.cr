class App::Organizations < App::Base
  base "/organizations"

  # Filters
  ###############################################################################################

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action, except: [:index, :index_html, :create, :accept_invite])]
  private def find_organization(id : String)
    @current_org = Models::Organization.find!(UUID.new(id))
    current_organization = @current_org
  end

  getter! current_org : Models::Organization

  @[AC::Route::Filter(:before_action, except: [:index, :index_html, :create, :accept_invite])]
  private def require_org_access
    require_organization_access!(current_org)
  end

  @[AC::Route::Filter(:before_action, only: [:add_member, :update_member, :remove_member, :invites, :create_invite, :revoke_invite])]
  private def require_manager
    require_permission!(current_org, Permissions::Manager)
  end

  @[AC::Route::Filter(:before_action, only: [:update, :destroy])]
  private def require_admin
    require_permission!(current_org, Permissions::Admin)
  end

  # Routes
  ###############################################################################################

  # List user's organizations
  @[AC::Route::GET("/", accept: "application/json")]
  def index : Array(Models::Organization)
    user_organizations.to_a
  end

  # Show organizations management page
  @[AC::Route::GET("/")]
  def index_html
    render html: File.read("views/organizations.html")
  end

  # Get organization details
  @[AC::Route::GET("/:id")]
  def show : Models::Organization
    current_org
  end

  # Create new organization
  @[AC::Route::POST("/", body: :org, status_code: HTTP::Status::CREATED)]
  def create(org : Models::Organization) : Models::Organization
    user = current_user.not_nil!
    org.owner_id = user.id
    org.save!

    # Add creator as admin
    org.add(user, Permissions::Admin)

    # Set as current organization
    current_organization = org

    org
  end

  # Update organization
  @[AC::Route::PATCH("/:id", body: :org)]
  @[AC::Route::PUT("/:id", body: :org)]
  def update(org : Models::Organization) : Models::Organization
    current = current_org
    current.assign_attributes(org)
    raise Error::ModelValidation.new(current.errors) unless current.save
    current
  end

  # Delete organization
  @[AC::Route::DELETE("/:id", status_code: HTTP::Status::ACCEPTED)]
  def destroy : Nil
    current_org.destroy
  end

  # Switch current organization
  @[AC::Route::POST("/:id/switch")]
  def switch : NamedTuple(message: String, organization: Models::Organization)
    {message: "Switched to organization", organization: current_org}
  end

  # List organization members
  @[AC::Route::GET("/:id/members")]
  def members : Array(Models::OrganizationUser)
    Models::OrganizationUser.where(organization_id: current_org.id).to_a
  end

  # Add member to organization
  @[AC::Route::POST("/:id/members", body: :params)]
  def add_member(params : AddMemberParams)
    user = Models::User.find!(UUID.new(params.user_id))
    current_org.add(user, params.permission || Permissions::User)
    {message: "Member added"}
  end

  # Update member permission
  @[AC::Route::PATCH("/:id/members/:user_id", body: :params)]
  def update_member(user_id : String, params : UpdateMemberParams)
    org_user = Models::OrganizationUser.find!({UUID.new(user_id), current_org.id})
    org_user.permission = params.permission
    org_user.save!
    {message: "Member permission updated"}
  end

  # Remove member from organization
  @[AC::Route::DELETE("/:id/members/:user_id", status_code: HTTP::Status::ACCEPTED)]
  def remove_member(user_id : String) : Nil
    user = Models::User.find!(UUID.new(user_id))

    # Prevent removing the owner
    raise Error::Forbidden.new("Cannot remove organization owner") if current_org.owner_id == user.id

    current_org.remove(user)
  end

  # List organization invites
  @[AC::Route::GET("/:id/invites")]
  def invites : Array(Models::OrganizationInvite)
    Models::OrganizationInvite.where(organization_id: current_org.id).to_a
  end

  # Create organization invite
  @[AC::Route::POST("/:id/invites", body: :params, status_code: HTTP::Status::CREATED)]
  def create_invite(params : InviteParams) : Models::OrganizationInvite
    current_org.invite(
      params.email,
      params.permission || Permissions::User,
      params.expires
    )
  end

  # Revoke organization invite
  @[AC::Route::DELETE("/:id/invites/:invite_id", status_code: HTTP::Status::ACCEPTED)]
  def revoke_invite(invite_id : String) : Nil
    invite = Models::OrganizationInvite.find!(UUID.new(invite_id))
    raise Error::NotFound.new("Invite not found") if invite.organization_id != current_org.id
    invite.destroy
  end

  # Accept organization invite
  @[AC::Route::POST("/invites/:invite_id/accept")]
  def accept_invite(
    invite_id : String,
    @[AC::Param::Info(description: "Secret token from invite")]
    secret : String,
  )
    user = current_user.not_nil!
    invite = Models::OrganizationInvite.find!(UUID.new(invite_id))

    # Verify secret
    raise Error::Forbidden.new("Invalid invite secret") if invite.secret != secret

    # Check expiration
    if expires = invite.expires
      raise Error::Forbidden.new("Invite has expired") if Time.utc > expires
    end

    # Accept invite
    invite.accept!(user)

    {message: "Invite accepted", organization: invite.organization}
  end

  # Parameter classes
  ###############################################################################################

  class AddMemberParams
    include JSON::Serializable
    include HTTP::Params::Serializable

    property user_id : String
    property permission : Permissions?
  end

  class UpdateMemberParams
    include JSON::Serializable
    include HTTP::Params::Serializable

    property permission : Permissions
  end

  class InviteParams
    include JSON::Serializable
    include HTTP::Params::Serializable

    property email : String
    property permission : Permissions?
    property expires : Time?
  end
end
