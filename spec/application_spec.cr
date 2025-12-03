require "./spec_helper"

describe App::Base do
  # ==============
  #  Unit Testing Authentication Helpers
  # ==============
  it "should return nil for current_user when not logged in" do
    controller = App::Welcome.spec_instance(HTTP::Request.new("GET", "/"))
    controller.current_user.should be_nil
  end

  it "should load current_user from session" do
    # Create test user
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "session@example.com"
    user.save!

    # Create request with session
    request = HTTP::Request.new("GET", "/")
    controller = App::Welcome.spec_instance(request)

    # Manually set session (simulating logged in user)
    controller.session["user_id"] = user.id.to_s

    # Should load user from session
    current = controller.current_user
    current.should_not be_nil
    current.try(&.id).should eq user.id
    current.try(&.email).should eq "session@example.com"

    # Clean up
    user.destroy
  end

  it "should cache current_user" do
    # Create test user
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "cache@example.com"
    user.save!

    request = HTTP::Request.new("GET", "/")
    controller = App::Welcome.spec_instance(request)
    controller.session["user_id"] = user.id.to_s

    # First call loads from database
    user1 = controller.current_user
    # Second call should return cached value
    user2 = controller.current_user

    user1.should eq user2
    user1.object_id.should eq user2.object_id

    # Clean up
    user.destroy
  end

  it "should return true for authenticated? when logged in" do
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "check@example.com"
    user.save!

    request = HTTP::Request.new("GET", "/")
    controller = App::Welcome.spec_instance(request)
    controller.session["user_id"] = user.id.to_s

    controller.authenticated?.should be_true

    # Clean up
    user.destroy
  end

  it "should return false for authenticated? when not logged in" do
    controller = App::Welcome.spec_instance(HTTP::Request.new("GET", "/"))
    controller.authenticated?.should be_false
  end
end
