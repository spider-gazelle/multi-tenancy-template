require "../spec_helper"

describe App::Models::Auth do
  auth = App::Models::Auth.new

  Spec.before_each do
    auth.destroy rescue nil
    auth = App::Models::Auth.new
  end

  it "should associate a user with an authentication source" do
    user = App::Models::User.new
    user.name = "Testing"
    user.email = "steve@auth.com"

    auth.provider = "google"
    auth.uid = "unique google string"
    auth.user = user
    auth.save!

    # user has_many works
    user.id.should_not be_nil
    user.auth_sources.map(&.uid).should contain(auth.uid)

    auth2 = App::Models::Auth.find!({auth.provider, auth.uid})
    auth2.uid.should eq auth.uid

    # user delete should destroy all auth models
    user.destroy
    App::Models::Auth.all.to_a.should be_empty
  end

  it "should store OAuth tokens" do
    user = App::Models::User.new
    user.name = "Testing"
    user.email = "steve@auth.com"

    auth.provider = "microsoft"
    auth.uid = "microsoft-user-id"
    auth.user = user
    auth.access_token = "access_token_value"
    auth.refresh_token = "refresh_token_value"
    auth.token_type = "Bearer"
    auth.token_expires_at = Time.utc + 1.hour
    auth.token_scope = "openid profile email"
    auth.save!

    auth2 = App::Models::Auth.find!({auth.provider, auth.uid})
    auth2.access_token.should eq "access_token_value"
    auth2.refresh_token.should eq "refresh_token_value"
    auth2.token_type.should eq "Bearer"
    auth2.token_scope.should eq "openid profile email"
  end

  it "should check if token is expired" do
    user = App::Models::User.new
    user.name = "Testing"
    user.email = "steve@auth.com"

    auth.provider = "google"
    auth.uid = "google-user-id"
    auth.user = user
    auth.access_token = "token"
    auth.token_expires_at = Time.utc - 1.hour # Expired
    auth.save!

    auth.token_expired?.should be_true
    auth.valid_token?.should be_false
  end

  it "should check if token is valid" do
    user = App::Models::User.new
    user.name = "Testing"
    user.email = "steve@auth.com"

    auth.provider = "google"
    auth.uid = "google-user-id"
    auth.user = user
    auth.access_token = "token"
    auth.token_expires_at = Time.utc + 1.hour # Not expired
    auth.save!

    auth.token_expired?.should be_false
    auth.valid_token?.should be_true
  end
end
