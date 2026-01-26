require "../spec_helper"

describe App::OAuthTokens do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::OAuthToken.clear
    App::Models::OAuthClient.clear
    App::Models::OrganizationUser.clear
    App::Models::Organization.clear
    App::Models::User.clear
  end

  describe "GET /oauth/tokens" do
    it "should require authentication" do
      result = client.get("/oauth/tokens")
      result.status_code.should eq 401
    end

    it "should return user's tokens" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token = create_test_token(user, oauth_client)

      result = authenticated_request(client, user, "GET", "/oauth/tokens")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"
    end

    it "should filter by client_id" do
      user = create_test_user("test@example.com")
      client1 = create_test_oauth_client("App 1")
      client2 = create_test_oauth_client("App 2")
      token1 = create_test_token(user, client1)
      token2 = create_test_token(user, client2)

      result = authenticated_request(client, user, "GET", "/oauth/tokens?client_id=#{client1.id}")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"
    end

    it "should exclude revoked tokens by default" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      active_token = create_test_token(user, oauth_client)
      revoked_token = create_test_token(user, oauth_client)
      revoked_token.revoked_at = Time.utc
      revoked_token.save!

      result = authenticated_request(client, user, "GET", "/oauth/tokens")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"
    end

    it "should include revoked tokens when requested" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      active_token = create_test_token(user, oauth_client)
      revoked_token = create_test_token(user, oauth_client)
      revoked_token.revoked_at = Time.utc
      revoked_token.save!

      result = authenticated_request(client, user, "GET", "/oauth/tokens?include_revoked=true")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "2"
    end

    it "should only return current user's tokens" do
      user1 = create_test_user("user1@example.com")
      user2 = create_test_user("user2@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token1 = create_test_token(user1, oauth_client)
      token2 = create_test_token(user2, oauth_client)

      result = authenticated_request(client, user1, "GET", "/oauth/tokens")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"
    end
  end

  describe "GET /oauth/tokens/by-application/:application_id" do
    it "should require organization manager permission" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user, App::Permissions::User)
      oauth_client = create_test_oauth_client_with_org("Test App", org)

      result = authenticated_request(client, user, "GET", "/oauth/tokens/by-application/#{oauth_client.id}")

      result.status_code.should eq 403
    end

    it "should return tokens for organization managers" do
      manager = create_test_user("manager@example.com")
      org = create_test_organization("Tech Corp", manager, App::Permissions::Manager)
      oauth_client = create_test_oauth_client_with_org("Test App", org)

      other_user = create_test_user("other@example.com")
      token = create_test_token(other_user, oauth_client)

      result = authenticated_request(client, manager, "GET", "/oauth/tokens/by-application/#{oauth_client.id}")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"
    end
  end

  describe "GET /oauth/tokens/:id" do
    it "should require authentication" do
      result = client.get("/oauth/tokens/#{UUID.random}")
      result.status_code.should eq 401
    end

    it "should show token details for owner" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token = create_test_token(user, oauth_client)

      result = authenticated_request(client, user, "GET", "/oauth/tokens/#{token.id}")

      result.status_code.should eq 200
      returned_token = App::Models::OAuthToken.from_json(result.body)
      returned_token.id.should eq token.id
    end

    it "should deny access to other user's tokens" do
      user1 = create_test_user("user1@example.com")
      user2 = create_test_user("user2@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token = create_test_token(user1, oauth_client)

      result = authenticated_request(client, user2, "GET", "/oauth/tokens/#{token.id}")

      result.status_code.should eq 403
    end
  end

  describe "POST /oauth/tokens/:id/revoke" do
    it "should revoke user's token" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token = create_test_token(user, oauth_client)
      token.revoked?.should be_false

      result = authenticated_request(client, user, "POST", "/oauth/tokens/#{token.id}/revoke")

      result.status_code.should eq 200
      token.reload!
      token.revoked?.should be_true
    end

    it "should return error for already revoked token" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token = create_test_token(user, oauth_client)
      token.revoked_at = Time.utc
      token.save!

      result = authenticated_request(client, user, "POST", "/oauth/tokens/#{token.id}/revoke")

      result.status_code.should eq 400
    end
  end

  describe "POST /oauth/tokens/revoke-all" do
    it "should revoke all user's tokens" do
      user = create_test_user("test@example.com")
      oauth_client = create_test_oauth_client("Test App")
      token1 = create_test_token(user, oauth_client)
      token2 = create_test_token(user, oauth_client)

      result = authenticated_request(client, user, "POST", "/oauth/tokens/revoke-all")

      result.status_code.should eq 200
      body = JSON.parse(result.body)
      body["revoked_count"].should eq 2
    end

    it "should filter by client_id when revoking" do
      user = create_test_user("test@example.com")
      client1 = create_test_oauth_client("App 1")
      client2 = create_test_oauth_client("App 2")
      token1 = create_test_token(user, client1)
      token2 = create_test_token(user, client2)

      result = authenticated_request(client, user, "POST", "/oauth/tokens/revoke-all?client_id=#{client1.id}")

      result.status_code.should eq 200
      body = JSON.parse(result.body)
      body["revoked_count"].should eq 1

      token1.reload!
      token2.reload!
      token1.revoked?.should be_true
      token2.revoked?.should be_false
    end
  end
end

# Helper methods
module OAuthTokensSpecHelper
  extend self

  def create_test_user(email : String)
    user = App::Models::User.new
    user.name = "Test User"
    user.email = email
    user.password = "password123"
    user.save!
    user
  end

  def create_test_organization(name : String, owner : App::Models::User, permission : App::Permissions = App::Permissions::Admin)
    org = App::Models::Organization.new
    org.name = name
    org.owner_id = owner.id
    org.save!

    org.add(owner, permission)

    org
  end

  def create_test_oauth_client(name : String)
    oauth_client = App::Models::OAuthClient.new
    oauth_client.name = name
    oauth_client.redirect_uris = ["https://example.com/callback"]
    oauth_client.scopes = ["public"]
    oauth_client.grant_types = ["authorization_code"]
    oauth_client.secret = "test-secret"
    oauth_client.save!
    oauth_client
  end

  def create_test_oauth_client_with_org(name : String, org : App::Models::Organization)
    oauth_client = App::Models::OAuthClient.new
    oauth_client.name = name
    oauth_client.redirect_uris = ["https://example.com/callback"]
    oauth_client.scopes = ["public"]
    oauth_client.grant_types = ["authorization_code"]
    oauth_client.organization_id = org.id
    oauth_client.secret = "test-secret"
    oauth_client.save!
    oauth_client
  end

  def create_test_token(user : App::Models::User, oauth_client : App::Models::OAuthClient)
    token = App::Models::OAuthToken.new
    token.token = Random::Secure.urlsafe_base64(32)
    token.token_type = "access_token"
    token.user_id = user.id
    token.client_id = oauth_client.id
    token.scopes = ["public"]
    token.expires_at = Time.utc + 1.hour
    token.save!
    token
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
end

include OAuthTokensSpecHelper
