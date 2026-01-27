require "ecr"

class App::OAuthConsent < App::Base
  base "/oauth/consent"

  @[AC::Route::Filter(:before_action)]
  private def authenticate
    require_auth!
  end

  # Display consent page for OAuth authorization
  @[AC::Route::GET("/")]
  def show(
    @[AC::Param::Info(description: "OAuth client ID")]
    client_id : String? = nil,
    @[AC::Param::Info(description: "Requested scopes")]
    scope : String = "",
    @[AC::Param::Info(description: "State parameter")]
    state : String? = nil,
    @[AC::Param::Info(description: "Redirect URI")]
    redirect_uri : String? = nil,
  ) : String
    unless client_id && state && redirect_uri
      raise Error::BadRequest.new("Missing required parameters")
    end
    raise Error::BadRequest.new("invalid client id") unless UUID.parse?(client_id)
    # Look up the OAuth client
    client = Models::OAuthClient.find?(UUID.new(client_id))
    raise Error::BadRequest.new("Unknown client") unless client

    # Parse scopes
    scopes = scope.split(" ").reject(&.empty?)

    # Template variables
    client_name = client.name
    user_email = current_user.try(&.email) || "Unknown user"
    redirect_host = URI.parse(redirect_uri).host || redirect_uri
    body = ECR.render("views/oauth_consent.ecr")
    render html: body
  end

  # Handle consent decision
  @[AC::Route::POST("/")]
  def submit(
    @[AC::Param::Info(description: "OAuth client ID")]
    client_id : String? = nil,
    @[AC::Param::Info(description: "Requested scopes")]
    scope : String = "",
    @[AC::Param::Info(description: "State parameter")]
    state : String? = nil,
    @[AC::Param::Info(description: "Redirect URI")]
    redirect_uri : String? = nil,
    @[AC::Param::Info(description: "User decision (approve or deny)")]
    decision : String? = nil,
  ) : Nil
    unless client_id && state && redirect_uri
      raise Error::BadRequest.new("Missing required parameters")
    end
    if decision == "approve"
      # User approved - redirect back to authorization endpoint with consent granted
      redirect_params = URI::Params.new
      redirect_params["client_id"] = client_id
      redirect_params["scope"] = scope
      redirect_params["state"] = state
      redirect_params["redirect_uri"] = redirect_uri
      redirect_params["consent"] = "granted"

      redirect_to "/oauth/authorize?#{redirect_params}"
    else
      # User denied - redirect back to client with error
      error_params = URI::Params.new
      error_params["error"] = "access_denied"
      error_params["error_description"] = "User denied the authorization request"
      error_params["state"] = state

      redirect_to "#{redirect_uri}?#{error_params}"
    end
  end
end
