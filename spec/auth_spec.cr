require "./spec_helper"

describe App::Auth do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::User.clear
  end

  # ==============
  #  Login Page
  # ==============
  it "should display login page" do
    result = client.get("/auth/login")
    result.status_code.should eq 200
    result.body.should contain("Welcome Back")
    result.body.should contain("Sign in with Google")
    result.body.should contain("Sign in with Microsoft")
  end

  it "should display error message on login page" do
    result = client.get("/auth/login?error=Invalid+credentials")
    result.status_code.should eq 200
    result.body.should contain("Invalid credentials")
  end

  # ==============
  #  Username/Password Login
  # ==============
  it "should login with valid credentials" do
    # Create test user
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "test@example.com"
    user.password = "password123"
    user.save!

    # Attempt login
    result = client.post("/auth/login",
      body: "email=test@example.com&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    result.status_code.should eq 303 # Changed to 303 (see_other)
    result.headers["Location"].should eq "/"
    result.headers["Set-Cookie"]?.should_not be_nil
  end

  it "should reject invalid password" do
    # Create test user
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "test@example.com"
    user.password = "password123"
    user.save!

    # Attempt login with wrong password
    result = client.post("/auth/login",
      body: "email=test@example.com&password=wrongpassword",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    result.status_code.should eq 303 # Changed to 303 (see_other)
    result.headers["Location"].should contain("/auth/login?error=")
  end

  it "should reject non-existent user" do
    result = client.post("/auth/login",
      body: "email=nonexistent@example.com&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    result.status_code.should eq 303 # Changed to 303 (see_other)
    result.headers["Location"].should contain("/auth/login?error=")
  end

  it "should normalize email on login" do
    # Create test user with lowercase email
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "test@example.com"
    user.password = "password123"
    user.save!

    # Login with uppercase email
    result = client.post("/auth/login",
      body: "email=TEST@EXAMPLE.COM&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    result.status_code.should eq 303 # Changed to 303 (see_other)
    result.headers["Location"].should eq "/"
  end

  # ==============
  #  Logout
  # ==============
  it "should logout and redirect to login" do
    result = client.get("/auth/logout")
    result.status_code.should eq 303
    result.headers["Location"].should eq "/auth/login"
  end

  it "should logout from OAuth provider" do
    result = client.get("/auth/logout?provider=microsoft")
    result.status_code.should eq 303
    result.headers["Location"].should contain("login.microsoftonline.com")
  end

  # ==============
  #  OAuth Initiation
  # ==============
  # Note: OAuth tests require environment variables to be set
  # GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET

  pending "should redirect to Google OAuth" do
    result = client.get("/auth/oauth/google")
    result.status_code.should eq 303
    result.headers["Location"].should contain("accounts.google.com")
    result.headers["Location"].should contain("oauth2")
  end

  pending "should redirect to Microsoft OAuth" do
    result = client.get("/auth/oauth/microsoft")
    result.status_code.should eq 303
    result.headers["Location"].should contain("login.microsoftonline.com")
    result.headers["Location"].should contain("oauth2")
  end
end
