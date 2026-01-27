require "http/server/handler"
require "authly"

module App
  # Custom Authly handler that mounts at /auth/oauth/* instead of /oauth/*
  # This is a copy of Authly::Handler with modified paths for consistent API routing
  class AuthlyHandler
    include HTTP::Handler

    def call(context)
      handle_route(context) || call_next(context)
    end

    private def handle_route(context) : Bool
      path = context.request.path

      case path
      when "/auth/oauth/authorize"
        handle_if_method(context, "GET") { Authly::AuthorizationHandler.handle(context) }
      when "/auth/oauth/token"
        handle_token_endpoint(context)
      when "/auth/oauth/par"
        handle_if_method(context, "POST") { Authly::PARHandler.handle(context) }
      when "/auth/oauth/device/code"
        handle_if_method(context, "POST") { Authly::DeviceAuthorizationHandler.handle(context) }
      when "/auth/device"
        handle_if_methods(context, ["GET", "POST"]) { Authly::DeviceVerificationHandler.handle(context) }
      when "/auth/introspect"
        handle_if_method(context, "POST") { Authly::IntrospectHandler.handle(context) }
      when "/auth/revoke"
        handle_if_method(context, "POST") { Authly::RevokeHandler.handle(context) }
      when "/auth/oauth/userinfo"
        handle_if_method(context, "GET") { Authly::UserInfoHandler.handle(context) }
      when "/auth/.well-known/openid-configuration"
        handle_if_method(context, "GET") { Authly::DiscoveryHandler.handle(context) }
      when "/auth/oauth/register"
        handle_registration_endpoint(context)
      else
        false
      end
    end

    private def handle_if_method(context, expected_method : String, &)
      return false unless context.request.method == expected_method
      yield
      true
    end

    private def handle_if_methods(context, expected_methods : Array(String), &)
      return false unless expected_methods.includes?(context.request.method)
      yield
      true
    end

    private def handle_token_endpoint(context) : Bool
      return false unless context.request.method == "POST"
      if context.request.form_params["grant_type"] == "refresh_token"
        Authly::RefreshTokenHandler.handle(context)
      else
        Authly::AccessTokenHandler.handle(context)
      end
      true
    end

    private def handle_registration_endpoint(context) : Bool
      return false unless context.request.method == "POST"
      return false unless Authly.config.allow_dynamic_registration?
      Authly::ClientRegistrationHandler.handle(context)
      true
    end
  end
end
