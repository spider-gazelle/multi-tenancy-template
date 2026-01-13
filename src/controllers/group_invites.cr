class App::GroupInvites < App::Base
  base "/group-invites"

  # GET /groups/invites/:id/accept?secret=xxx
  @[AC::Route::GET("/:id/accept")]
  def show(
    id : String,
    @[AC::Param::Info(description: "Invite secret token")]
    secret : String,
  )
    invite = Models::GroupInvite.find!(UUID.new(id))

    unless invite.secret == secret
      raise Error::Forbidden.new("Invalid invite secret")
    end

    if invite.expired?
      raise Error::Forbidden.new("Invite has expired")
    end

    group = invite.group
    organization = group.organization

    # If user is logged in, accept invite directly
    if user = current_user
      invite.accept!(user)
      redirect_to "/organizations/#{organization.id}/groups/#{group.id}"
    else
      # Show accept invite page for non-logged in users
      html = File.read("views/accept_group_invite.html")
      render html: html
    end
  end

  # POST /groups/invites/:id/accept
  @[AC::Route::POST("/:id/accept")]
  def accept(
    id : String,
    @[AC::Param::Info(description: "Invite secret token")]
    secret : String,
  )
    invite = Models::GroupInvite.find!(UUID.new(id))

    unless invite.secret == secret
      raise Error::Forbidden.new("Invalid invite secret")
    end

    if invite.expired?
      raise Error::Forbidden.new("Invite has expired")
    end

    user = current_user.not_nil!
    invite.accept!(user)
    group = invite.group
    organization = group.organization

    redirect_to "/organizations/#{organization.id}/groups/#{group.id}"
  end
end
