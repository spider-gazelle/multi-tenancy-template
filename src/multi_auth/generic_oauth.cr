require "oauth2"
require "json"
require "http/client"

module App
  # Generic OAuth2 provider implementation that doesn't depend on multi_auth providers
  # This allows database-driven OAuth2 configuration without loading built-in providers
  class GenericOauthProvider
    getter provider_config : App::Models::Oauth2Provider
    getter redirect_uri : String

    def initialize(@redirect_uri : String, @provider_config : App::Models::Oauth2Provider)
    end

    def authorize_uri(scope = nil, state = nil) : String
      scope ||= provider_config.scopes

      # Parse the site to get host and port
      uri = URI.parse(provider_config.site)
      host = uri.host || "localhost"
      port = uri.port
      tls = uri.scheme == "https"

      client = OAuth2::Client.new(
        host,
        provider_config.client_id,
        provider_config.client_secret,
        port: port,
        scheme: tls ? "https" : "http",
        authorize_uri: provider_config.authorize_url,
        redirect_uri: redirect_uri
      )

      client.get_authorize_uri(scope, state)
    end

    def user(params : Hash(String, String)) : OAuthUser
      # Parse the site to get host and port for token exchange
      uri = URI.parse(provider_config.site)
      host = uri.host || "localhost"
      port = uri.port
      tls = uri.scheme == "https"

      # Determine auth scheme based on authentication_scheme
      auth_scheme = case provider_config.authentication_scheme.downcase
                    when "request body"
                      OAuth2::AuthScheme::RequestBody
                    when "basic auth"
                      OAuth2::AuthScheme::HTTPBasic
                    else
                      OAuth2::AuthScheme::RequestBody
                    end

      client = OAuth2::Client.new(
        host,
        provider_config.client_id,
        provider_config.client_secret,
        port: port,
        scheme: tls ? "https" : "http",
        token_uri: provider_config.token_url,
        redirect_uri: redirect_uri,
        auth_scheme: auth_scheme
      )

      access_token = client.get_access_token_using_authorization_code(params["code"])

      # Fetch user profile
      # Check if user_profile_url is a full URL or a relative path
      profile_url = provider_config.user_profile_url
      if profile_url.starts_with?("http://") || profile_url.starts_with?("https://")
        # Full URL provided
        profile_uri = URI.parse(profile_url)
        profile_host = profile_uri.host.not_nil!
        profile_port = profile_uri.port
        profile_tls = profile_uri.scheme == "https"
        profile_path = profile_uri.path || "/"
      else
        # Relative path, use site as base
        profile_host = host
        profile_port = port
        profile_tls = tls
        profile_path = profile_url
      end

      api = HTTP::Client.new(profile_host, port: profile_port, tls: profile_tls)
      access_token.authenticate(api)

      raw_json = api.get(profile_path).body

      build_user(raw_json)
    end

    private def build_user(raw_json : String) : OAuthUser
      json = JSON.parse(raw_json)

      # Get info mappings
      mappings = provider_config.info_mappings_hash

      # Extract user information based on mappings
      uid = extract_field(json, mappings["uid"]? || "id")
      name = extract_field(json, mappings["name"]? || "name")
      email = extract_field(json, mappings["email"]? || "email")

      # Create user with provider identifier
      OAuthUser.new(
        provider: provider_config.provider_string,
        uid: uid.to_s,
        name: name.try(&.to_s),
        email: email.try(&.to_s),
        raw_json: raw_json
      )
    end

    # Extract field from JSON using dot notation (e.g., "user.profile.name")
    private def extract_field(json : JSON::Any, path : String) : JSON::Any?
      return nil if path.empty?

      parts = path.split(".")
      current = json

      parts.each do |part|
        if current.as_h?
          current = current[part]?
          return nil unless current
        else
          return nil
        end
      end

      current
    rescue KeyError
      nil
    end
  end

  # Simple user struct for OAuth responses
  struct OAuthUser
    getter provider : String
    getter uid : String
    getter name : String?
    getter email : String?
    getter raw_json : String

    def initialize(@provider : String, @uid : String, @name : String?, @email : String?, @raw_json : String)
    end
  end
end
