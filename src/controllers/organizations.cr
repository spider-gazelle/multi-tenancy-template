class App::Organizations < App::Base
  base "/organizations"

  # Filters
  ###############################################################################################

  @[AC::Route::Filter(:before_action, except: [:lookup])]
  private def authenticate
    require_auth!
  end

  @[AC::Route::Filter(:before_action, except: [:index, :index_html, :create, :accept_invite, :lookup])]
  private def find_organization(id : String)
    @current_org = Models::Organization.find!(UUID.new(id))
    current_organization = @current_org
  end

  getter! current_org : Models::Organization

  @[AC::Route::Filter(:before_action, except: [:index, :index_html, :create, :accept_invite, :lookup])]
  private def require_org_access
    require_organization_access!(current_org)
  end

  @[AC::Route::Filter(:before_action, only: [:add_member, :update_member, :remove_member, :create_invite, :revoke_invite])]
  private def require_manager
    require_permission!(current_org, Permissions::Manager)
  end

  @[AC::Route::Filter(:before_action, only: [:update, :destroy])]
  private def require_admin
    require_permission!(current_org, Permissions::Admin)
  end

  @[AC::Route::Filter(:before_action, only: [:create_group, :update_group, :destroy_group, :add_group_user, :remove_group_user, :create_group_invite])]
  private def require_group_management
    unless current_org.user_can_manage_groups?(current_user.not_nil!)
      raise Error::Forbidden.new("Insufficient permissions to manage groups")
    end
  end

  @[AC::Route::Filter(:before_action, only: [:show_group, :update_group, :destroy_group, :group_users, :add_group_user, :remove_group_user, :create_group_invite])]
  private def find_group(group_id : String)
    @current_group = Models::Group.find_by(id: UUID.new(group_id), organization_id: current_org.id)
  end

  getter! current_group : Models::Group

  # Routes
  ###############################################################################################

  # List user's organizations (JSON API) with search and pagination
  @[AC::Route::GET("/list")]
  def index
    user = current_user.not_nil!
    params = search_params

    # Get organization IDs for the user using pluck (server-side)
    org_ids = Models::OrganizationUser
      .where(user_id: user.id)
      .pluck(:organization_id)
      .to_set
      .to_a

    # Return empty if user has no organizations
    if org_ids.empty?
      response.headers["X-Total-Count"] = "0"
      response.headers["Content-Range"] = "organizations 0-0/0"
      return [] of Models::Organization
    end

    # Build query for organizations using IN clause
    query = Models::Organization.where(id: org_ids)

    # Apply search
    query = apply_search(query, params["q"].as(String), params["fields"].as(Array(String)))

    # Apply sorting
    query = apply_sort(query, params["sort"].as(String), params["order"].as(String))

    # Paginate and return results
    paginate_results(query, "organizations", "/organizations/list")
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

  # Show organization management page
  @[AC::Route::GET("/:id/manage")]
  def manage
    render html: File.read("views/organization_manage.html")
  end

  # Show organization settings page
  @[AC::Route::GET("/:id/settings")]
  def settings
    render html: File.read("views/organization_settings.html")
  end

  # Create new organization
  @[AC::Route::POST("/", body: :org, status_code: HTTP::Status::CREATED)]
  def create(org : Models::Organization) : Models::Organization
    user = current_user.not_nil!
    org.owner_id = user.id
    org.save!

    # Create admin group and add creator as admin
    admin_group = org.create_admin_group!

    # Also add to organization_users for backward compatibility
    org.add(user, Permissions::Admin)

    # Set as current organization
    current_organization = org

    audit_log(Models::AuditLog::Actions::CREATE, Models::AuditLog::Resources::ORGANIZATION, org.id, org)
    org
  end

  # Update organization
  @[AC::Route::PATCH("/:id", body: :org)]
  @[AC::Route::PUT("/:id", body: :org)]
  def update(org : Models::Organization) : Models::Organization
    current = current_org
    current.assign_attributes(org)
    raise Error::ModelValidation.new(current.errors) unless current.save
    audit_log(Models::AuditLog::Actions::UPDATE, Models::AuditLog::Resources::ORGANIZATION, current.id, current)
    current
  end

  # Delete organization
  @[AC::Route::DELETE("/:id", status_code: HTTP::Status::ACCEPTED)]
  def destroy : Nil
    org_id = current_org.id
    current_org.destroy
    audit_log(Models::AuditLog::Actions::DELETE, Models::AuditLog::Resources::ORGANIZATION, org_id)
  end

  # Switch current organization
  @[AC::Route::POST("/:id/switch")]
  def switch : NamedTuple(message: String, organization: Models::Organization)
    {message: "Switched to organization", organization: current_org}
  end

  record LookupResponse, id : UUID, name : String, subdomain : String? do
    include JSON::Serializable
  end

  # Resolve subdomain to Organization ID (Public)
  @[AC::Route::GET("/lookup")]
  def lookup(
    @[AC::Param::Info(description: "Subdomain to lookup")]
    subdomain : String,
  ) : LookupResponse
    # Find organization by subdomain
    org = Models::Organization.find_by?(subdomain: subdomain)
    raise Error::NotFound.new("Organization not found") unless org

    LookupResponse.new(
      id: org.id,
      name: org.name,
      subdomain: org.subdomain,
    )
  end

  # List organization members
  @[AC::Route::GET("/:id/members")]
  def members : Array(MemberResponse)
    Models::OrganizationUser.where(organization_id: current_org.id).to_a.map do |org_user|
      MemberResponse.new(org_user)
    end
  end

  # Add member to organization
  @[AC::Route::POST("/:id/members", body: :params)]
  def add_member(params : AddMemberParams)
    user = Models::User.find!(UUID.new(params.user_id))
    current_org.add(user, params.permission || Permissions::User)
    audit_log(Models::AuditLog::Actions::JOIN, Models::AuditLog::Resources::MEMBER, user.id, current_org)
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
    audit_log(Models::AuditLog::Actions::LEAVE, Models::AuditLog::Resources::MEMBER, user.id, current_org)
  end

  # List organization invites
  @[AC::Route::GET("/:id/invites")]
  def invites : Array(Models::OrganizationInvite)
    Models::OrganizationInvite.where(organization_id: current_org.id).to_a
  end

  # Create organization invite
  @[AC::Route::POST("/:id/invites", body: :params, status_code: HTTP::Status::CREATED)]
  def create_invite(params : InviteParams) : Models::OrganizationInvite
    invite = current_org.invite(
      params.email,
      params.permission || Permissions::User,
      params.expires
    )
    audit_log(Models::AuditLog::Actions::INVITE, Models::AuditLog::Resources::INVITE, invite.id, current_org)
    invite
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

  # Group Routes
  ###############################################################################################

  # Groups management page
  @[AC::Route::GET("/:id/groups")]
  def groups_html
    render html: File.read("views/groups.html")
  end

  # List groups (JSON API)
  @[AC::Route::GET("/:id/groups/list")]
  def groups : Array(Models::Group)
    user = current_user.not_nil!
    if current_org.user_can_manage_groups?(user)
      current_org.groups.to_a
    else
      user.groups_in_organization(current_org).to_a
    end
  end

  # Get group details
  @[AC::Route::GET("/:id/groups/:group_id")]
  def show_group : Models::Group
    current_group
  end

  # Create group
  @[AC::Route::POST("/:id/groups", body: :group, status_code: HTTP::Status::CREATED)]
  def create_group(group : Models::Group) : Models::Group
    group.organization_id = current_org.id
    group.save!
    group
  end

  # Update group
  @[AC::Route::PATCH("/:id/groups/:group_id", body: :group)]
  @[AC::Route::PUT("/:id/groups/:group_id", body: :group)]
  def update_group(group : Models::Group) : Models::Group
    current = current_group

    if current.admin_group? && group.permission != Permissions::Admin
      raise Error::Forbidden.new("Cannot change admin group permission level")
    end

    current.assign_attributes(group)
    raise Error::ModelValidation.new(current.errors) unless current.save
    current
  end

  # Delete group
  @[AC::Route::DELETE("/:id/groups/:group_id", status_code: HTTP::Status::ACCEPTED)]
  def destroy_group : Nil
    raise Error::Forbidden.new("Cannot delete admin group") if current_group.admin_group?
    current_group.destroy
  end

  # List group users
  @[AC::Route::GET("/:id/groups/:group_id/users")]
  def group_users : Array(Models::User)
    current_group.users.to_a
  end

  # Add user to group
  @[AC::Route::POST("/:id/groups/:group_id/users", body: :params)]
  def add_group_user(params : AddGroupUserParams) : Models::GroupUser
    user = Models::User.find!(UUID.new(params.user_id))

    unless current_org.users.where(id: user.id).exists?
      raise Error::Forbidden.new("User must be a member of the organization first")
    end

    if current_group.user_is_member?(user)
      raise Error::Forbidden.new("User is already a member of this group")
    end

    current_group.add_user(user, params.is_admin || false)
    Models::GroupUser.find!({current_group.id, user.id})
  end

  # Remove user from group
  @[AC::Route::DELETE("/:id/groups/:group_id/users/:user_id", status_code: HTTP::Status::ACCEPTED)]
  def remove_group_user(user_id : String) : Nil
    user = Models::User.find!(UUID.new(user_id))

    if current_group.admin_group?
      admin_count = current_group.admins.count
      if admin_count <= 1 && current_group.user_is_admin?(user)
        raise Error::Forbidden.new("Cannot remove the last administrator from admin group")
      end
    end

    current_group.remove_user(user)
  end

  # Create group invite
  @[AC::Route::POST("/:id/groups/:group_id/invites", body: :params, status_code: HTTP::Status::CREATED)]
  def create_group_invite(params : GroupInviteParams) : Models::GroupInvite
    expires = params.expires_in_hours ? Time.utc + params.expires_in_hours.not_nil!.hours : nil
    invite = current_group.invite(params.email, expires)
    Services::EmailService.send_group_invite(invite, current_user.not_nil!)
    invite
  end

  # Response classes
  ###############################################################################################

  struct MemberResponse
    include JSON::Serializable

    getter user_id : UUID
    getter organization_id : UUID
    getter permission : Permissions
    getter created_at : Time?
    getter user : UserInfo?

    struct UserInfo
      include JSON::Serializable

      getter id : UUID
      getter name : String
      getter email : String

      def initialize(@id, @name, @email)
      end
    end

    def initialize(org_user : Models::OrganizationUser)
      @user_id = org_user.user_id
      @organization_id = org_user.organization_id
      @permission = org_user.permission
      @created_at = org_user.created_at
      if u = org_user.user
        @user = UserInfo.new(u.id, u.name, u.email)
      end
    end
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

  class AddGroupUserParams
    include JSON::Serializable
    include HTTP::Params::Serializable

    property user_id : String
    property is_admin : Bool?
  end

  class GroupInviteParams
    include JSON::Serializable
    include HTTP::Params::Serializable

    property email : String
    property expires_in_hours : Int32?
  end
end
