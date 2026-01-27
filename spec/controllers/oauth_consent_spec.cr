require "../spec_helper"

describe App::OAuthConsent do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::OAuthToken.clear
    App::Models::OAuthClient.clear
    App::Models::OrganizationUser.clear
    App::Models::Organization.clear
    App::Models::User.clear
  end

  describe "GET /oauth/consent" do
    it "should require authentication" do
      result = client.get("/oauth/consent?client_id=test&scope=public&state=abc&redirect_uri=https://example.com/callback")
      result.status_code.should eq 401
    end

    it "should require client_id parameter" do
      user = create_test_user("test@example.com")

      result = authenticated_request(client, user, "GET", "/oauth/consent?scope=public&state=abc&redirect_uri=https://example.com/callback")

      result.status_code.should eq 400
    end

    it "should require state parameter" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")

      result = authenticated_request(client, user, "GET", "/oauth/consent?client_id=#{oauth_client.id}&scope=public&redirect_uri=https://example.com/callback")

      result.status_code.should eq 400
    end

    it "should require redirect_uri parameter" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")

      result = authenticated_request(client, user, "GET", "/oauth/consent?client_id=#{oauth_client.id}&scope=public&state=abc")

      result.status_code.should eq 400
    end

    it "should return error for unknown client" do
      user = create_test_user("test@example.com")

      result = authenticated_request(client, user, "GET", "/oauth/consent?client_id=unknown-client&scope=public&state=abc&redirect_uri=https://example.com/callback")

      result.status_code.should eq 400
    end

    it "should display consent page for valid request" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("My OAuth App")

      result = authenticated_request(client, user, "GET", "/oauth/consent?client_id=#{oauth_client.id}&scope=public+read&state=xyz123&redirect_uri=https://example.com/callback")

      result.status_code.should eq 200
      content_type = result.headers["Content-Type"]?
      content_type.should_not be_nil
      content_type.not_nil!.should contain("text/html")
      result.body.should contain("My OAuth App")
      result.body.should contain("test@example.com")
      result.body.should contain("public")
      result.body.should contain("read")
    end
  end

  describe "POST /oauth/consent" do
    it "should require authentication" do
      result = client.post("/oauth/consent",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"},
        body: "client_id=test&scope=public&state=abc&redirect_uri=https://example.com/callback&decision=approve"
      )
      result.status_code.should eq 401
    end

    it "should redirect to authorize endpoint on approval" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")

      result = authenticated_request_with_form(client, user, "POST", "/oauth/consent", {
        "client_id"    => oauth_client.id.to_s,
        "scope"        => "public read",
        "state"        => "xyz123",
        "redirect_uri" => "https://example.com/callback",
        "decision"     => "approve",
      })

      result.status_code.should eq 302
      location = result.headers["Location"]?
      location.should_not be_nil
      location.not_nil!.should contain("/oauth/authorize")
      location.not_nil!.should contain("consent=granted")
      location.not_nil!.should contain("state=xyz123")
    end

    it "should redirect to client with error on denial" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")

      result = authenticated_request_with_form(client, user, "POST", "/oauth/consent", {
        "client_id"    => oauth_client.id.to_s,
        "scope"        => "public",
        "state"        => "xyz123",
        "redirect_uri" => "https://example.com/callback",
        "decision"     => "deny",
      })

      result.status_code.should eq 302
      location = result.headers["Location"]?
      location.should_not be_nil
      location.not_nil!.should contain("https://example.com/callback")
      location.not_nil!.should contain("error=access_denied")
      location.not_nil!.should contain("state=xyz123")
    end
  end
end

# Helper methods
module OAuthConsentSpecHelper
  extend self

  def create_test_user(email : String)
    user = App::Models::User.new
    user.name = "Test User"
    user.email = email
    user.password = "password123"
    user.save!
    user
  end

  def create_test_oauth_client(name : String)
    oauth_client = App::Models::OAuthClient.new
    oauth_client.name = name
    oauth_client.redirect_uris = ["https://example.com/callback"]
    oauth_client.scopes = ["public", "read", "write"]
    oauth_client.grant_types = ["authorization_code"]
    oauth_client.secret = "test-secret"
    oauth_client.save!
    oauth_client
  end

  def authenticated_request(client, user : App::Models::User, method : String, path : String)
    # Login to get session cookie
    login_result = client.post("/auth/login",
      body: "email=#{user.email}&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    # Extract session cookie
    cookie = login_result.headers["Set-Cookie"]?
    raise "Login failed - no session cookie" unless cookie

    # Make authenticated request
    headers = HTTP::Headers{"Cookie" => cookie}

    case method.upcase
    when "GET"
      client.get(path, headers: headers)
    when "POST"
      client.post(path, headers: headers)
    else
      raise "Unsupported method: #{method}"
    end
  end

  def authenticated_request_with_form(client, user : App::Models::User, method : String, path : String, form_data : Hash(String, String))
    # Login to get session cookie
    login_result = client.post("/auth/login",
      body: "email=#{user.email}&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    # Extract session cookie
    cookie = login_result.headers["Set-Cookie"]?
    raise "Login failed - no session cookie" unless cookie

    # Build form body
    form_body = form_data.map { |k, v| "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}" }.join("&")

    # Make authenticated request with form data
    headers = HTTP::Headers{
      "Cookie"       => cookie,
      "Content-Type" => "application/x-www-form-urlencoded",
    }

    case method.upcase
    when "POST"
      client.post(path, headers: headers, body: form_body)
    else
      raise "Unsupported method for form: #{method}"
    end
  end
end

include OAuthConsentSpecHelper
