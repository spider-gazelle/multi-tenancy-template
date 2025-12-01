# description of the welcome klass
class App::Welcome < App::Base
  base "/"

  # A welcome message
  @[AC::Route::GET("/")]
  def index
    user = current_user

    output = if user
               html = File.read("views/home.html")
               html = html.gsub("{{USER_NAME}}", HTML.escape(user.name))
               html = html.gsub("{{USER_EMAIL}}", HTML.escape(user.email))

               # Add provider info if logged in via OAuth
               provider = session["auth_provider"]?.try(&.to_s)
               if provider && (provider == "google" || provider == "microsoft")
                 provider_name = provider.capitalize
                 html = html.gsub("{{AUTH_PROVIDER_INFO}}", "<br><small>via #{provider_name}</small>")
                 html = html.gsub("{{LOGOUT_PROVIDER}}", "?provider=#{provider}")
               else
                 html = html.gsub("{{AUTH_PROVIDER_INFO}}", "")
                 html = html.gsub("{{LOGOUT_PROVIDER}}", "")
               end

               # Add organization info
               if org = current_organization
                 org_info = %(<div class="user-info" style="margin-top: 1rem;"><strong>Current Organization:</strong> #{HTML.escape(org.name)}</div>)
                 html = html.gsub("{{ORGANIZATION_INFO}}", org_info)
               else
                 html = html.gsub("{{ORGANIZATION_INFO}}", "")
               end

               html
             else
               File.read("views/home-guest.html")
             end

    render html: output
  end

  # For API applications the return value of the function is expected to work with
  # all of the responder blocks (see application.cr)
  # the various responses are returned based on the Accepts header
  @[AC::Route::GET("/api/:example")]
  @[AC::Route::POST("/api/:example")]
  @[AC::Route::GET("/api/other/route")]
  def api(example : Int32) : NamedTuple(result: Int32)
    {
      result: example,
    }
  end

  # this file is built as part of the docker build
  OPENAPI = YAML.parse(File.exists?("openapi.yml") ? File.read("openapi.yml") : "{}")

  # returns the OpenAPI representation of this service
  @[AC::Route::GET("/openapi")]
  def openapi : YAML::Any
    OPENAPI
  end
end
