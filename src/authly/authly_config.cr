require "authly"
require "../models/user"
require "../models/oauth_client"
require "../models/organization"
require "../models/organization_user"
require "../models/group"
require "../models/group_user"

module App
  # Custom Authorizable Owner implementation
  class AuthlyOwner
    include Authly::AuthorizableOwner

    # Authenticate user by username/password
    # Returns user_id on success, nil on failure
    def authorized?(username : String, password : String) : String?
      user = Models::User.where(email: username.strip.downcase).first?
      return nil unless user
      return nil unless user.verify_password(password)
      user.id.to_s
    end

    def id_token(user_id : String) : Hash(String, String | Int64)
      user = Models::User.find(UUID.new(user_id))

      created_at = Time.utc.to_unix
      expires_at = created_at + Authly.config.access_ttl.total_seconds.to_i64

      {
        "iss"   => Authly.config.issuer,
        "iat"   => created_at,
        "exp"   => expires_at,
        "sub"   => user.id.to_s,
        "aud"   => Authly.config.issuer,
        "name"  => user.name,
        "email" => user.email,
      }
    end
  end

  # Custom Authorizable Client implementation
  class AuthlyClient
    include Authly::AuthorizableClient
    include Enumerable(Models::OAuthClient)

    def each(&)
      Models::OAuthClient.all.each { |client| yield client }
    end

    def valid_redirect?(client_id : String, redirect_uri : String) : Bool
      client = Models::OAuthClient.find?(UUID.new(client_id))
      return false unless client
      client.redirect_uris.includes?(redirect_uri)
    end

    def authorized?(client_id : String, client_secret : String)
      client = Models::OAuthClient.find?(UUID.new(client_id))
      return false unless client
      client.active? && client.verify_secret(client_secret)
    end

    def allowed_scopes?(client_id : String, scopes : String) : Bool
      client = Models::OAuthClient.find?(UUID.new(client_id))
      return false unless client

      requested_scopes = scopes.split(" ")
      requested_scopes.all? { |scope| client.scopes.includes?(scope) }
    end

    def allowed_grant_type?(client_id : String, grant_type : String) : Bool
      client = Models::OAuthClient.find?(UUID.new(client_id))
      return false unless client

      client.grant_types.includes?(grant_type)
    end
  end

  # Custom Claims Provider - adds user metadata to JWT tokens
  class AuthlyClaimsProvider
    include Authly::ClaimsProvider

    def enrich_access_token(
      payload : Authly::JWTPayload,
      client_id : String,
      sub : String,
      scope : String,
    ) : Authly::JWTPayload
      # Get user for metadata
      user = begin
        Models::User.find?(UUID.new(sub))
      rescue
        nil
      end

      return payload unless user

      # Get user's roles/groups across all organizations
      user_roles = [] of String

      # Add organization-specific roles
      org_users = Models::OrganizationUser.where(user_id: user.id).to_a
      org_users.each do |orgu|
        org = Models::Organization.find?(orgu.organization_id)
        next unless org
        # Format: "org:{org_id}:{permission}"
        user_roles << "org:#{org.id}:#{orgu.permission.to_s.downcase}"
      end

      # Add group-based roles
      group_users = Models::GroupUser.where(user_id: user.id).to_a
      group_users.each do |grpu|
        group = Models::Group.find?(grpu.group_id)
        next unless group
        org = Models::Organization.find?(group.organization_id)
        next unless org
        # Format: "org:{org_id}:{permission}" and "group:{group_id}"
        user_roles << "org:#{org.id}:#{group.permission.to_s.downcase}"
        user_roles << "group:#{group.id}"
      end

      user_roles = user_roles.uniq

      # Generate permissions bitflags
      permissions = 0_i64
      permissions |= 1 if user.support   # Bit 0 = support flag
      permissions |= 2 if user.sys_admin # Bit 1 = sys_admin flag

      # Add custom user metadata claim
      payload["u"] = {
        "n" => user.name,   # Name
        "e" => user.email,  # Email
        "p" => permissions, # Permissions bitflags
        "r" => user_roles,  # Roles/groups
      }

      payload
    end
  end

  # Custom Token Store - stores tokens in database for persistence and revocation
  class AuthlyTokenStore
    include Authly::TokenStore

    def store(token_id : String, payload)
      # Handle different payload types flexibly
      data = case payload
             when Hash(String, String | Int64 | Bool | Float64)
               payload
             when Hash
               # Convert any hash to the expected type
               result = {} of String => (String | Int64 | Bool | Float64)
               payload.each do |k, v|
                 key = k.to_s
                 result[key] = case v
                               when String  then v
                               when Int64   then v
                               when Int32   then v.to_i64
                               when Bool    then v
                               when Float64 then v
                               else              v.to_s
                               end
               end
               result
             else
               raise "Unexpected payload type: #{payload.class}"
             end

      expires_at = if exp = data["exp"]?
                     exp_value = exp.is_a?(Int64) ? exp : exp.to_s.to_i64
                     Time.unix(exp_value)
                   else
                     Time.utc + 1.hour
                   end

      # Extract user_id from sub claim
      user_id = if sub = data["sub"]?
                  sub_str = sub.is_a?(String) ? sub : sub.to_s
                  UUID.new(sub_str) rescue nil
                else
                  nil
                end

      # Extract client_id
      client_id = if cid = data["cid"]?
                    cid.is_a?(String) ? cid : cid.to_s
                  else
                    nil
                  end

      # Extract scope
      scopes = if scope = data["scope"]?
                 scope_str = scope.is_a?(String) ? scope : scope.to_s
                 scope_str.split(" ")
               else
                 [] of String
               end

      # Store token with jti for revocation tracking
      Models::OAuthToken.create(
        token: token_id,
        token_type: data["token_type"]?.try { |tok| tok.is_a?(String) ? tok : tok.to_s } || "access_token",
        user_id: user_id,
        client_id: client_id ? UUID.new(client_id) : nil,
        scopes: scopes,
        expires_at: expires_at,
        metadata: data.transform_keys(&.to_s).transform_values(&.to_s)
      )
    end

    def fetch(token_id : String)
      token_record = Models::OAuthToken.find_by_token?(token_id)
      raise Authly::Error.invalid_token unless token_record && token_record.token_valid?

      # Convert metadata back to expected type
      result = {} of String => (String | Int64 | Bool | Float64)
      token_record.metadata.each do |k, v|
        result[k] = case v
                    when /^\d+$/ then v.to_i64
                    when "true"  then true
                    when "false" then false
                    else              v
                    end
      end
      result
    end

    def revoke(token_id : String)
      # Look up by token or by jti in metadata
      token = Models::OAuthToken.find_by_token?(token_id)
      if token
        token.update(revoked_at: Time.utc)
      else
        Models::OAuthToken.where("metadata->>'jti' = ?", token_id).update_all(revoked_at: Time.utc)
      end
    end

    def revoked?(token_id : String) : Bool
      token = Models::OAuthToken.find_by_token?(token_id)
      return token.revoked? if token

      token_by_jti = Models::OAuthToken.where("metadata->>'jti' = ?", token_id).first?
      token_by_jti ? token_by_jti.revoked? : false
    end

    def valid?(token_id : String) : Bool
      token = Models::OAuthToken.find_by_token?(token_id)
      return token.token_valid? if token

      token_by_jti = Models::OAuthToken.where("metadata->>'jti' = ?", token_id).first?
      token_by_jti ? token_by_jti.token_valid? : false
    end
  end

  # Configure Authly
  def self.configure_authly
    algorithm, secret_key = detect_jwt_config(JWT_SECRET)

    Authly.configure do |config|
      config.issuer = JWT_ISSUER
      config.base_url = APP_BASE_URL
      config.secret_key = secret_key
      config.public_key = secret_key
      config.algorithm = algorithm
      config.token_strategy = :jwt
      config.access_ttl = 2.hours
      config.refresh_ttl = 30.days
      config.code_ttl = 10.minutes
      config.owners = AuthlyOwner.new
      config.clients = AuthlyClient.new
      config.token_store = AuthlyTokenStore.new
      config.claims_provider = AuthlyClaimsProvider.new # Custom JWT claims
      config.persist_jwt_tokens = true                  # Enable JWT persistence
      config.enforce_pkce = false
      config.enforce_pkce_s256 = false
      config.require_certificate_bound_tokens = false
      config.allow_dynamic_registration = false
    end
  end

  private def self.detect_jwt_config(jwt_secret : String) : Tuple(JWT::Algorithm, String)
    begin
      if jwt_secret.size > 100 && !jwt_secret.includes?(" ") && !jwt_secret.includes?("-")
        decoded = Base64.decode_string(jwt_secret)
        if decoded.includes?("BEGIN") || decoded.includes?("begin")
          return {JWT::Algorithm::RS256, decoded}
        end
      end
    rescue
    end

    {JWT::Algorithm::HS256, jwt_secret}
  end
end
