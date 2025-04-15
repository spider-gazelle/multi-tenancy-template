require "../spec_helper"

describe App::Models::Auth do
  auth = App::Models::Auth.new

  Spec.around_each do |test|
    auth = App::Models::Auth.new
    test.run
    auth.destroy
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
end
