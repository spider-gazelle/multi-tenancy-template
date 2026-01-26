require "./spec_helper"

describe "Authly OAuth2/OIDC Integration" do
  describe "OAuth Client Management" do
    it "creates an OAuth client with hashed secret" do
      client = App::Models::OAuthClient.new(
        name: "Test Application",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public", "read", "write"],
        grant_types: ["authorization_code", "refresh_token"],
        active: true
      )
      client.secret = "my-secret"
      client.save!

      client.persisted?.should be_true
      client.secret_hash.should_not be_nil
      client.verify_secret("my-secret").should be_true
      client.verify_secret("wrong-secret").should be_false
    end

    it "validates redirect URIs" do
      client = App::Models::OAuthClient.new(
        name: "Test App",
        redirect_uris: ["https://example.com/callback", "https://example.com/oauth"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      authly_client = App::AuthlyClient.new
      authly_client.valid_redirect?(client.id.to_s, "https://example.com/callback").should be_true
      authly_client.valid_redirect?(client.id.to_s, "https://example.com/oauth").should be_true
      authly_client.valid_redirect?(client.id.to_s, "https://evil.com/callback").should be_false
    end

    it "validates client credentials" do
      client = App::Models::OAuthClient.new(
        name: "Test App",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["client_credentials"],
        active: true
      )
      client.secret = "correct-secret"
      client.save!

      authly_client = App::AuthlyClient.new
      authly_client.authorized?(client.id.to_s, "correct-secret").should be_true
      authly_client.authorized?(client.id.to_s, "wrong-secret").should be_false
      authly_client.authorized?(UUID.v7.to_s, "correct-secret").should be_false
    end

    it "validates allowed scopes" do
      client = App::Models::OAuthClient.new(
        name: "Test App",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public", "read", "write"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      authly_client = App::AuthlyClient.new
      authly_client.allowed_scopes?(client.id.to_s, "public").should be_true
      authly_client.allowed_scopes?(client.id.to_s, "public read").should be_true
      authly_client.allowed_scopes?(client.id.to_s, "public read write").should be_true
      authly_client.allowed_scopes?(client.id.to_s, "admin").should be_false
      authly_client.allowed_scopes?(client.id.to_s, "public admin").should be_false
    end

    it "validates allowed grant types" do
      client = App::Models::OAuthClient.new(
        name: "Test App",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code", "refresh_token"],
        active: true
      )
      client.secret = "secret"
      client.save!

      authly_client = App::AuthlyClient.new
      authly_client.allowed_grant_type?(client.id.to_s, "authorization_code").should be_true
      authly_client.allowed_grant_type?(client.id.to_s, "refresh_token").should be_true
      authly_client.allowed_grant_type?(client.id.to_s, "client_credentials").should be_false
      authly_client.allowed_grant_type?(client.id.to_s, "password").should be_false
    end

    it "checks if client is active" do
      active_client = App::Models::OAuthClient.new(
        name: "Active App",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: true
      )
      active_client.secret = "secret"
      active_client.save!

      inactive_client = App::Models::OAuthClient.new(
        name: "Inactive App",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: false
      )
      inactive_client.secret = "secret"
      inactive_client.save!

      authly_client = App::AuthlyClient.new
      authly_client.authorized?(active_client.id.to_s, "secret").should be_true
      authly_client.authorized?(inactive_client.id.to_s, "secret").should be_false
    end
  end

  describe "OAuth Token Management" do
    it "stores and retrieves tokens" do
      user = create_user("token-user@example.com", "Token User")

      # Create the OAuth client first to satisfy foreign key constraint
      client = App::Models::OAuthClient.new(
        name: "Test Client",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public", "read"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      token_data = {
        "token_type" => "access_token",
        "sub"        => user.id.to_s,
        "cid"        => client.id.to_s,
        "scope"      => "public read",
        "exp"        => (Time.utc + 1.hour).to_unix,
      }

      store = App::AuthlyTokenStore.new
      store.store("test-token-123", token_data)

      token_record = App::Models::OAuthToken.find_by_token?("test-token-123")
      token_record.should_not be_nil
      token_record.not_nil!.user_id.should eq(user.id)
      token_record.not_nil!.client_id.should eq(client.id)
      token_record.not_nil!.scopes.should eq(["public", "read"])
    end

    it "checks token validity" do
      user = create_user("validity-user@example.com", "Validity User")

      # Create OAuth client for foreign key constraint
      client = App::Models::OAuthClient.new(
        name: "Test Client",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      # Valid token with jti in metadata
      valid_jti = "valid-jti-123"
      valid_token = App::Models::OAuthToken.create(
        token: "valid-token",
        token_type: "access_token",
        user_id: user.id,
        client_id: client.id,
        scopes: ["public"],
        expires_at: Time.utc + 1.hour,
        metadata: {"jti" => valid_jti}
      )

      # Expired token
      expired_jti = "expired-jti-123"
      expired_token = App::Models::OAuthToken.create(
        token: "expired-token",
        token_type: "access_token",
        user_id: user.id,
        client_id: client.id,
        scopes: ["public"],
        expires_at: Time.utc - 1.hour,
        metadata: {"jti" => expired_jti}
      )

      # Revoked token
      revoked_jti = "revoked-jti-123"
      revoked_token = App::Models::OAuthToken.create(
        token: "revoked-token",
        token_type: "access_token",
        user_id: user.id,
        client_id: client.id,
        scopes: ["public"],
        expires_at: Time.utc + 1.hour,
        revoked_at: Time.utc,
        metadata: {"jti" => revoked_jti}
      )

      store = App::AuthlyTokenStore.new
      store.valid?(valid_jti).should be_true
      store.valid?(expired_jti).should be_false
      store.valid?(revoked_jti).should be_false
      store.valid?("nonexistent-jti").should be_false
    end

    it "revokes tokens" do
      user = create_user("revoke-user@example.com", "Revoke User")

      # Create OAuth client for foreign key constraint
      client = App::Models::OAuthClient.new(
        name: "Test Client",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      jti = "jti-to-revoke-123"
      token = App::Models::OAuthToken.create(
        token: "token-to-revoke",
        token_type: "access_token",
        user_id: user.id,
        client_id: client.id,
        scopes: ["public"],
        expires_at: Time.utc + 1.hour,
        metadata: {"jti" => jti}
      )

      store = App::AuthlyTokenStore.new
      store.valid?(jti).should be_true
      store.revoked?(jti).should be_false

      store.revoke(jti)

      store.valid?(jti).should be_false
      store.revoked?(jti).should be_true
    end

    it "checks token expiration" do
      user = create_user("expiry-user@example.com", "Expiry User")

      # Create OAuth client for foreign key constraint
      client = App::Models::OAuthClient.new(
        name: "Test Client",
        redirect_uris: ["https://example.com/callback"],
        scopes: ["public"],
        grant_types: ["authorization_code"],
        active: true
      )
      client.secret = "secret"
      client.save!

      token = App::Models::OAuthToken.create(
        token: "expiring-token",
        token_type: "access_token",
        user_id: user.id,
        client_id: client.id,
        scopes: ["public"],
        expires_at: Time.utc + 1.second,
        metadata: {} of String => String
      )

      token.expired?.should be_false

      sleep 2.seconds

      token_reloaded = App::Models::OAuthToken.find_by_token?("expiring-token")
      token_reloaded.not_nil!.expired?.should be_true
    end
  end

  describe "User Authentication" do
    it "authenticates users with correct credentials" do
      user = App::Models::User.new
      user.name = "Auth User"
      user.email = "auth-user@example.com"
      user.password = "correct-password"
      user.save!

      owner = App::AuthlyOwner.new
      # authorized? now returns user_id (String) on success, nil on failure
      result = owner.authorized?("auth-user@example.com", "correct-password")
      result.should_not be_nil
      result.should eq(user.id.to_s)
      owner.authorized?("auth-user@example.com", "wrong-password").should be_nil
      owner.authorized?("nonexistent@example.com", "any-password").should be_nil
    end

    it "generates ID tokens with user claims" do
      user = create_user("idtoken-user@example.com", "ID Token User")

      owner = App::AuthlyOwner.new
      id_token_claims = owner.id_token(user.id.to_s)

      id_token_claims["sub"].should eq(user.id.to_s)
      id_token_claims["name"].should eq(user.name)
      id_token_claims["email"].should eq(user.email)
      id_token_claims["iss"].should eq(Authly.config.issuer)
      id_token_claims["iat"].should be_a(Int64)
      id_token_claims["exp"].should be_a(Int64)
    end

    it "normalizes email addresses" do
      user = App::Models::User.new
      user.name = "Normalize User"
      user.email = "normalize@example.com"
      user.password = "password"
      user.save!

      owner = App::AuthlyOwner.new
      # Should work with different casing - authorized? returns user_id on success
      owner.authorized?("NORMALIZE@EXAMPLE.COM", "password").should_not be_nil
      owner.authorized?("Normalize@Example.Com", "password").should_not be_nil
      owner.authorized?("  normalize@example.com  ", "password").should_not be_nil
    end
  end

  describe "Authly Configuration" do
    it "configures Authly with correct settings" do
      Authly.config.issuer.should_not be_empty
      Authly.config.secret_key.should_not be_empty
      # Algorithm depends on JWT_SECRET format (HS256 for plain secret, RS256 for private key)
      Authly.config.algorithm.should be_a(JWT::Algorithm)
      Authly.config.token_strategy.should eq(:jwt)
      Authly.config.access_ttl.should eq(2.hours)
      Authly.config.refresh_ttl.should eq(30.days)
      Authly.config.code_ttl.should eq(10.minutes)
    end

    it "uses custom implementations" do
      Authly.config.owners.should be_a(App::AuthlyOwner)
      Authly.config.clients.should be_a(App::AuthlyClient)
      Authly.config.token_store.should be_a(App::AuthlyTokenStore)
    end
  end
end
