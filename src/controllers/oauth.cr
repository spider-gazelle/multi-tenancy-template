require "../multi_auth/generic_oauth"

class App::OAuth < App::Base
  base "/auth/oauth"

  # Redirect to OAuth provider authorization page
  @[AC::Route::GET("/:id")]
  def authorize(id : String) : Nil
    provider = find_provider(id)

    # Create the generic OAuth provider instance
    oauth_provider = App::GenericOauthProvider.new(
      redirect_uri: callback_url(id),
      provider_config: provider
    )

    # Redirect to OAuth provider's authorization page
    redirect_to oauth_provider.authorize_uri
  end

  # OAuth callback handler
  @[AC::Route::GET("/:id/callback")]
  def callback(id : String, code : String, state : String? = nil)
    provider = find_provider(id)

    # Create the generic OAuth provider instance
    oauth_provider = App::GenericOauthProvider.new(
      redirect_uri: callback_url(id),
      provider_config: provider
    )

    # Get user info from OAuth provider
    oauth_user = oauth_provider.user(request.query_params.to_h)

    # Find or create user in a transaction
    user = nil

    # First, try to find existing auth record outside transaction to ensure visibility
    provider_str = provider.provider_string
    uid_str = oauth_user.uid

    # Use a simple query that won't trigger compiler bugs
    existing_auth = App::Models::Auth
      .where("provider = $1 AND uid = $2", provider_str, uid_str)
      .limit(1)
      .to_a
      .first?

    if existing_auth
      # User already exists via this OAuth provider
      user = existing_auth.user!

      # Ensure user is part of the organization
      PgORM::Database.transaction do |_tx|
        org_user = App::Models::OrganizationUser.find?({user.not_nil!.id, provider.organization_id})
        unless org_user
          App::Models::OrganizationUser.new(
            user_id: user.not_nil!.id,
            organization_id: provider.organization_id,
            permission: App::Permissions::User
          ).save!
        end
      end
    else
      # No existing auth, check for user by email and create auth + org membership in transaction
      PgORM::Database.transaction do |_tx|
        # Check if user exists by email (for linking existing accounts)
        existing_user = if email = oauth_user.email
                          # Normalize email to match User model's before_save normalization
                          normalized_email = email.strip.downcase
                          App::Models::User.where("email = ?", normalized_email).first?
                        end

        if existing_user
          # Link existing user to this OAuth provider
          user = existing_user
        else
          # Create new user
          user = App::Models::User.new(
            name: oauth_user.name || oauth_user.email || "User",
            email: oauth_user.email || "#{oauth_user.uid}@#{provider.provider_string}"
          )
          user.save!
        end

        # Create auth record linking this OAuth identity to the user
        App::Models::Auth.new(
          provider: provider_str,
          uid: uid_str,
          user_id: user.not_nil!.id
        ).save!

        # Ensure user is part of the organization
        org_user = App::Models::OrganizationUser.find?({user.not_nil!.id, provider.organization_id})
        unless org_user
          App::Models::OrganizationUser.new(
            user_id: user.not_nil!.id,
            organization_id: provider.organization_id,
            permission: App::Permissions::User
          ).save!
        end
      end
    end

    # Return success message with user info
    {
      success: true,
      user:    {
        id:    user.not_nil!.id.to_s,
        name:  user.not_nil!.name,
        email: user.not_nil!.email,
      },
      provider: provider.provider_string,
    }
  end

  # Helper to find OAuth provider by ID
  private def find_provider(id : String) : App::Models::Oauth2Provider
    provider_id = UUID.new(id)
    App::Models::Oauth2Provider.find!(provider_id)
  rescue ArgumentError
    raise AC::Route::Param::ValueError.new("Invalid UUID format for provider id", "id", "UUID")
  rescue PgORM::Error::RecordNotFound
    raise AC::Route::Param::ValueError.new("Provider not found", "id", "existing provider")
  end

  # Helper to generate callback URL
  private def callback_url(id : String) : String
    # Construct the full callback URL based on the request
    scheme = request.headers["X-Forwarded-Proto"]? || "http"
    host = request.headers["Host"]? || "localhost"
    "#{scheme}://#{host}/auth/oauth/#{id}/callback"
  end
end
