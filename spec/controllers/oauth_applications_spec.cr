require "../spec_helper"

describe App::OAuthApplications do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::OAuthToken.clear
    App::Models::OAuthClient.clear
    App::Models::OrganizationUser.clear
    App::Models::Organization.clear
    App::Models::User.clear
  end

  describe "GET /oauth/applications" do
    it "should require authentication" do
      result = client.get("/oauth/applications")
      result.status_code.should eq 401
    end

    it "should return applications for user's organizations" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      app = create_test_oauth_client("Test App", org)

      result = authenticated_request(client, user, "GET", "/oauth/applications")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"

      apps = Array(App::Models::OAuthClient).from_json(result.body)
      apps.size.should eq 1
      apps[0].name.should eq "Test App"
    end

    it "should return empty array when user has no organizations" do
      user = create_test_user("test@example.com")

      result = authenticated_request(client, user, "GET", "/oauth/applications")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "0"
    end

    it "should allow system admin to see all applications" do
      admin = create_test_user("admin@example.com")
      admin.sys_admin = true
      admin.save!

      user = create_test_user("user@example.com")
      org = create_test_organization("Other Corp", user)
      app = create_test_oauth_client("Other App", org)

      result = authenticated_request(client, admin, "GET", "/oauth/applications")

      result.status_code.should eq 200
      apps = Array(App::Models::OAuthClient).from_json(result.body)
      apps.any? { |a| a.name == "Other App" }.should be_true
    end
  end

  describe "GET /oauth/applications/:id" do
    it "should require authentication" do
      result = client.get("/oauth/applications/test-id")
      result.status_code.should eq 401
    end

    it "should show application details" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      app = create_test_oauth_client("Test App", org)

      result = authenticated_request(client, user, "GET", "/oauth/applications/#{app.id}")

      result.status_code.should eq 200
      returned_app = App::Models::OAuthClient.from_json(result.body)
      returned_app.name.should eq "Test App"
    end

    it "should deny access to other organization's applications" do
      user1 = create_test_user("user1@example.com")
      org1 = create_test_organization("Org 1", user1)
      app1 = create_test_oauth_client("App 1", org1)

      user2 = create_test_user("user2@example.com")

      result = authenticated_request(client, user2, "GET", "/oauth/applications/#{app1.id}")
      result.status_code.should eq 403
    end
  end

  describe "POST /oauth/applications" do
    it "should require authentication" do
      result = client.post("/oauth/applications",
        headers: HTTP::Headers{"Content-Type" => "application/json"},
        body: {name: "New App"}.to_json
      )
      result.status_code.should eq 401
    end

    it "should create application and return client secret" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)

      result = authenticated_request_with_json(client, user, "POST", "/oauth/applications", {
        name:            "New OAuth App",
        redirect_uris:   ["https://example.com/callback"],
        scopes:          ["public", "read"],
        grant_types:     ["authorization_code"],
        organization_id: org.id,
      })

      result.status_code.should eq 201
      body = JSON.parse(result.body)
      body["name"].should eq "New OAuth App"
      body["client_secret"].should_not be_nil
      body["client_secret"].as_s.size.should be > 10
    end

    it "should require organization_id for non-admin users" do
      user = create_test_user("test@example.com")

      result = authenticated_request_with_json(client, user, "POST", "/oauth/applications", {
        name:          "New App",
        redirect_uris: ["https://example.com/callback"],
        scopes:        ["public"],
        grant_types:   ["authorization_code"],
      })

      result.status_code.should eq 400
    end
  end

  describe "PATCH /oauth/applications/:id" do
    it "should update application" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      app = create_test_oauth_client("Old Name", org)

      result = authenticated_request_with_json(client, user, "PATCH", "/oauth/applications/#{app.id}", {
        name: "New Name",
      })

      result.status_code.should eq 200
      updated = App::Models::OAuthClient.from_json(result.body)
      updated.name.should eq "New Name"
    end
  end

  describe "DELETE /oauth/applications/:id" do
    it "should delete application" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      app = create_test_oauth_client("Test App", org)
      app_id = app.id

      result = authenticated_request(client, user, "DELETE", "/oauth/applications/#{app_id}")

      result.status_code.should eq 202
      App::Models::OAuthClient.find?(app_id).should be_nil
    end
  end

  describe "POST /oauth/applications/:id/regenerate-secret" do
    it "should regenerate client secret" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      app = create_test_oauth_client("Test App", org)

      result = authenticated_request(client, user, "POST", "/oauth/applications/#{app.id}/regenerate-secret")

      result.status_code.should eq 200
      body = JSON.parse(result.body)
      body["client_secret"].should_not be_nil
    end
  end
end

# Helper methods
module OAuthApplicationsSpecHelper
  extend self

  def create_test_user(email : String)
    user = App::Models::User.new
    user.name = "Test User"
    user.email = email
    user.password = "password123"
    user.save!
    user
  end

  def create_test_organization(name : String, owner : App::Models::User)
    org = App::Models::Organization.new
    org.name = name
    org.owner_id = owner.id
    org.save!

    # Add owner as admin (Manager permission required for OAuth app management)
    org.add(owner, App::Permissions::Admin)

    org
  end

  def create_test_oauth_client(name : String, org : App::Models::Organization)
    client = App::Models::OAuthClient.new
    client.name = name
    client.redirect_uris = ["https://example.com/callback"]
    client.scopes = ["public"]
    client.grant_types = ["authorization_code"]
    client.organization_id = org.id
    client.secret = "test-secret"
    client.save!
    client
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
    when "PATCH"
      client.patch(path, headers: headers)
    when "PUT"
      client.put(path, headers: headers)
    when "DELETE"
      client.delete(path, headers: headers)
    else
      raise "Unsupported method: #{method}"
    end
  end

  def authenticated_request_with_json(client, user : App::Models::User, method : String, path : String, body)
    # Login to get session cookie
    login_result = client.post("/auth/login",
      body: "email=#{user.email}&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    # Extract session cookie
    cookie = login_result.headers["Set-Cookie"]?
    raise "Login failed - no session cookie" unless cookie

    # Make authenticated request with JSON body
    headers = HTTP::Headers{
      "Cookie"       => cookie,
      "Content-Type" => "application/json",
    }

    case method.upcase
    when "POST"
      client.post(path, headers: headers, body: body.to_json)
    when "PATCH"
      client.patch(path, headers: headers, body: body.to_json)
    when "PUT"
      client.put(path, headers: headers, body: body.to_json)
    else
      raise "Unsupported method for JSON: #{method}"
    end
  end
end

include OAuthApplicationsSpecHelper
