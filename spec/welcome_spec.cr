require "./spec_helper"

describe App::Welcome do
  # ==============
  #  Unit Testing
  # ==============
  it "should generate a date string" do
    # instantiate the controller you wish to unit test
    welcome = App::Welcome.spec_instance(HTTP::Request.new("GET", "/"))

    # Test the instance methods of the controller
    welcome.set_date_header.should contain("GMT")
  end

  # ==============
  # Test Responses
  # ==============
  client = AC::SpecHelper.client

  # optional, use to change the response type
  headers = HTTP::Headers{
    "Accept" => "application/yaml",
  }

  it "should show guest page when not logged in" do
    result = client.get("/")
    result.status_code.should eq 200
    result.body.should contain("Spider-Gazelle Multitenancy Starter")
    result.body.should contain("Production-ready template")
    result.body.should contain("/auth/login")
  end

  it "should show user info when logged in" do
    # Create and login user
    user = App::Models::User.new
    user.name = "Test User"
    user.email = "welcome@example.com"
    user.password = "password123"
    user.save!

    # Login
    login_result = client.post("/auth/login",
      body: "email=welcome@example.com&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    # Get cookies from login response
    cookies = login_result.headers.get?("Set-Cookie")

    if cookies
      # Visit home page with session cookie
      result = client.get("/", headers: HTTP::Headers{"Cookie" => cookies.first})
      result.status_code.should eq 200
      result.body.should contain("Test User")
      result.body.should contain("welcome@example.com")
      result.body.should contain("/auth/logout")
    end

    # Clean up
    user.destroy
  end

  it "should return HTML for home page" do
    result = client.get("/")
    result.status_code.should eq 200
    content_type = result.headers["Content-Type"]?
    content_type.should_not be_nil
    content_type.to_s.should contain("text/html")
    result.headers["Date"].should_not be_nil
  end

  it "should extract params for you" do
    result = client.post("/api/400")
    JSON.parse(result.body).should eq({"result" => 400})
  end
end
