require "./spec_helper"
require "webmock"

describe App::OAuth do
  client = AC::SpecHelper.client

  it "should redirect to OAuth provider authorization page" do
    # Create test organization
    org = App::Models::Organization.new(
      name: "Test Organization",
      description: "Test org for OAuth"
    )
    org.save!

    # Create OAuth provider configuration
    provider = App::Models::Oauth2Provider.new(
      organization_id: org.id,
      name: "Microsoft AAD",
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      site: "https://login.microsoftonline.com",
      authorize_url: "/common/oauth2/v2.0/authorize",
      token_url: "/common/oauth2/v2.0/token",
      token_method: "POST",
      authentication_scheme: "Request Body",
      user_profile_url: "https://graph.microsoft.com/v1.0/me",
      scopes: "openid offline_access profile email",
      info_mappings: JSON.parse(%({"uid": "id", "email": "userPrincipalName", "name": "displayName"}))
    )
    provider.save!

    # Test the authorize endpoint
    result = client.get("/auth/oauth/#{provider.id}")

    # Should redirect to OAuth provider
    result.status_code.should eq(302)
    location = result.headers["Location"]
    location.should contain("login.microsoftonline.com")
    location.should contain("client_id=test-client-id")
    location.should contain("scope=openid")
  end

  it "should handle OAuth callback and create user" do
    # Create test organization
    org = App::Models::Organization.new(
      name: "Test Organization",
      description: "Test org for OAuth"
    )
    org.save!

    # Create OAuth provider configuration
    provider = App::Models::Oauth2Provider.new(
      organization_id: org.id,
      name: "Microsoft AAD",
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      site: "https://login.microsoftonline.com",
      authorize_url: "/common/oauth2/v2.0/authorize",
      token_url: "/common/oauth2/v2.0/token",
      token_method: "POST",
      authentication_scheme: "Request Body",
      user_profile_url: "https://graph.microsoft.com/v1.0/me",
      scopes: "openid offline_access profile email",
      info_mappings: JSON.parse(%({"uid": "id", "email": "userPrincipalName", "name": "displayName"}))
    )
    provider.save!

    # Mock OAuth token exchange
    WebMock.stub(:post, "https://login.microsoftonline.com/common/oauth2/v2.0/token")
      .to_return(
        status: 200,
        body: {
          access_token:  "test-access-token",
          token_type:    "Bearer",
          expires_in:    3600,
          refresh_token: "test-refresh-token",
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock user profile fetch
    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/me")
      .with(headers: {"Authorization" => "Bearer test-access-token"})
      .to_return(
        status: 200,
        body: {
          id:                "test-user-123",
          displayName:       "Test User",
          userPrincipalName: "test@example.com",
          mail:              "test@example.com",
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Test the callback endpoint
    result = client.get("/auth/oauth/#{provider.id}/callback?code=test-auth-code&state=test-state")

    result.status_code.should eq(200)

    # Parse response
    response = JSON.parse(result.body)
    response["success"].should eq(true)
    response["provider"].should eq("oauth-#{provider.id}")

    # Verify user was created
    user_id = response["user"]["id"].as_s
    user = App::Models::User.find!(UUID.new(user_id))
    user.name.should eq("Test User")
    user.email.should eq("test@example.com")

    # Verify auth record was created
    auth = App::Models::Auth.find!({"oauth-#{provider.id}", "test-user-123"})
    auth.user_id.should eq(user.id)

    # Verify user is part of organization
    org_user = App::Models::OrganizationUser.find!({user.id, org.id})
    org_user.organization_id.should eq(org.id)
    org_user.permission.should eq(App::Permissions::User)
  end

  it "should handle OAuth callback for existing user" do
    # Create test organization
    org = App::Models::Organization.new(
      name: "Test Organization",
      description: "Test org for OAuth"
    )
    org.save!

    # Create existing user
    existing_user = App::Models::User.new(
      name: "Existing User",
      email: "existing@example.com"
    )
    existing_user.save!

    # Create OAuth provider configuration
    provider = App::Models::Oauth2Provider.new(
      organization_id: org.id,
      name: "Microsoft AAD",
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      site: "https://login.microsoftonline.com",
      authorize_url: "/common/oauth2/v2.0/authorize",
      token_url: "/common/oauth2/v2.0/token",
      token_method: "POST",
      authentication_scheme: "Request Body",
      user_profile_url: "https://graph.microsoft.com/v1.0/me",
      scopes: "openid offline_access profile email",
      info_mappings: JSON.parse(%({"uid": "id", "email": "userPrincipalName", "name": "displayName"}))
    )
    provider.save!

    # Create auth record for existing user
    existing_auth = App::Models::Auth.new(
      provider: "oauth-#{provider.id}",
      uid: "existing-user-123",
      user_id: existing_user.id
    )
    existing_auth.save!

    # Mock OAuth token exchange
    WebMock.stub(:post, "https://login.microsoftonline.com/common/oauth2/v2.0/token")
      .to_return(
        status: 200,
        body: {
          access_token:  "test-access-token",
          token_type:    "Bearer",
          expires_in:    3600,
          refresh_token: "test-refresh-token",
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock user profile fetch
    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/me")
      .with(headers: {"Authorization" => "Bearer test-access-token"})
      .to_return(
        status: 200,
        body: {
          id:                "existing-user-123",
          displayName:       "Existing User Updated",
          userPrincipalName: "existing@example.com",
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Test the callback endpoint
    result = client.get("/auth/oauth/#{provider.id}/callback?code=test-auth-code&state=test-state")

    result.status_code.should eq(200)

    # Parse response
    response = JSON.parse(result.body)
    response["success"].should eq(true)

    # Verify existing user was returned (not created)
    user_id = response["user"]["id"].as_s
    UUID.new(user_id).should eq(existing_user.id)

    # Verify auth record exists
    auth = App::Models::Auth.find!({"oauth-#{provider.id}", "existing-user-123"})
    auth.user_id.should eq(existing_user.id)

    # Verify user is part of organization
    org_user = App::Models::OrganizationUser.find!({existing_user.id, org.id})
    org_user.organization_id.should eq(org.id)
  end

  it "should handle nested JSON mappings" do
    # Create test organization
    org = App::Models::Organization.new(
      name: "Test Organization",
      description: "Test org for OAuth"
    )
    org.save!

    # Create OAuth provider with nested field mappings
    provider = App::Models::Oauth2Provider.new(
      organization_id: org.id,
      name: "Custom OAuth",
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      site: "https://oauth.example.com",
      authorize_url: "/authorize",
      token_url: "/token",
      token_method: "POST",
      authentication_scheme: "Request Body",
      user_profile_url: "https://api.example.com/user",
      scopes: "profile email",
      info_mappings: JSON.parse(%({"uid": "user.id", "email": "user.email", "name": "user.profile.name", "image": "user.avatar.url"}))
    )
    provider.save!

    # Mock OAuth token exchange
    WebMock.stub(:post, "https://oauth.example.com/token")
      .to_return(
        status: 200,
        body: {
          access_token: "test-access-token",
          token_type:   "Bearer",
          expires_in:   3600,
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock user profile fetch with nested structure
    WebMock.stub(:get, "https://api.example.com/user")
      .with(headers: {"Authorization" => "Bearer test-access-token"})
      .to_return(
        status: 200,
        body: {
          user: {
            id:      "nested-user-456",
            email:   "nested@example.com",
            profile: {
              name: "Nested User",
            },
            avatar: {
              url: "https://example.com/avatar.jpg",
            },
          },
        }.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Test the callback endpoint
    result = client.get("/auth/oauth/#{provider.id}/callback?code=test-auth-code")

    result.status_code.should eq(200)

    # Parse response
    response = JSON.parse(result.body)
    response["success"].should eq(true)
    response["user"]["name"].should eq("Nested User")
    response["user"]["email"].should eq("nested@example.com")
  end

  it "should return 404 for non-existent provider" do
    random_uuid = UUID.random

    result = client.get("/auth/oauth/#{random_uuid}")

    # Should return 400 Bad Request for invalid provider ID
    result.status_code.should eq(400)

    # Parse error response
    response = JSON.parse(result.body)
    response["parameter"].as_s.should eq("id")
    response["restriction"].as_s.should eq("existing provider")
  end
end
