require "../spec_helper"

describe App::Organizations do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::OrganizationUser.clear
    App::Models::Organization.clear
    App::Models::User.clear
  end

  describe "GET /organizations/list" do
    it "should return empty array when user has no organizations" do
      user = create_test_user("test@example.com")

      result = authenticated_request(client, user, "GET", "/organizations/list")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "0"
      result.headers["Content-Range"].should eq "organizations 0-0/0"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 0
    end

    it "should return user's organizations" do
      user = create_test_user("test@example.com")
      org1 = create_test_organization("Tech Corp", user)
      org2 = create_test_organization("Startup Inc", user)

      result = authenticated_request(client, user, "GET", "/organizations/list")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "2"
      result.headers["Content-Range"].should eq "organizations 0-1/2"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 2
    end

    it "should paginate results" do
      user = create_test_user("test@example.com")
      5.times { |i| create_test_organization("Org #{i}", user) }

      # First page
      result = authenticated_request(client, user, "GET", "/organizations/list?limit=2&offset=0")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "5"
      result.headers["Content-Range"].should eq "organizations 0-1/5"
      result.headers["Link"]?.should_not be_nil
      result.headers["Link"].should contain("offset=2")

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 2

      # Second page
      result = authenticated_request(client, user, "GET", "/organizations/list?limit=2&offset=2")

      result.status_code.should eq 200
      result.headers["Content-Range"].should eq "organizations 2-3/5"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 2
    end

    it "should search organizations by name" do
      user = create_test_user("test@example.com")
      create_test_organization("Tech Corporation", user)
      create_test_organization("Startup Inc", user)
      create_test_organization("Technology Solutions", user)

      result = authenticated_request(client, user, "GET", "/organizations/list?q=tech")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "2"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 2
      orgs.all? { |o| o.name.downcase.includes?("tech") }.should be_true
    end

    it "should search organizations by description" do
      user = create_test_user("test@example.com")
      org1 = create_test_organization("Company A", user)
      org1.description = "A technology company"
      org1.save!

      org2 = create_test_organization("Company B", user)
      org2.description = "A retail business"
      org2.save!

      result = authenticated_request(client, user, "GET", "/organizations/list?q=technology")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 1
      orgs[0].name.should eq "Company A"
    end

    it "should search in specific fields" do
      user = create_test_user("test@example.com")
      org1 = create_test_organization("Tech Corp", user)
      org1.description = "A retail company"
      org1.save!

      org2 = create_test_organization("Retail Inc", user)
      org2.description = "A technology company"
      org2.save!

      # Search only in name field
      result = authenticated_request(client, user, "GET", "/organizations/list?q=tech&fields=name")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 1
      orgs[0].name.should eq "Tech Corp"
    end

    it "should sort organizations" do
      user = create_test_user("test@example.com")
      create_test_organization("Zebra Corp", user)
      create_test_organization("Apple Inc", user)
      create_test_organization("Microsoft", user)

      # Sort ascending
      result = authenticated_request(client, user, "GET", "/organizations/list?sort=name&order=asc")

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs[0].name.should eq "Apple Inc"
      orgs[2].name.should eq "Zebra Corp"

      # Sort descending
      result = authenticated_request(client, user, "GET", "/organizations/list?sort=name&order=desc")

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs[0].name.should eq "Zebra Corp"
      orgs[2].name.should eq "Apple Inc"
    end

    it "should combine search, sort, and pagination" do
      user = create_test_user("test@example.com")
      5.times { |i| create_test_organization("Tech Company #{i}", user) }
      3.times { |i| create_test_organization("Retail Store #{i}", user) }

      result = authenticated_request(client, user, "GET", "/organizations/list?q=tech&sort=name&order=asc&limit=2&offset=0")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "5"
      result.headers["Content-Range"].should eq "organizations 0-1/5"

      orgs = Array(App::Models::Organization).from_json(result.body)
      orgs.size.should eq 2
      orgs.all? { |o| o.name.includes?("Tech") }.should be_true
    end

    it "should require authentication" do
      result = client.get("/organizations/list")
      result.status_code.should eq 401
    end
  end
  describe "GET /organizations/lookup" do
    it "returns organization details for valid subdomain" do
      org = App::Models::Organization.new(
        name: "Test Org",
        subdomain: "test-lookup"
      )
      org.save!

      response = client.get("/organizations/lookup?subdomain=test-lookup")
      response.status_code.should eq(200)
      result = JSON.parse(response.body)
      result["id"].as_s.should eq(org.id.to_s)
      result["name"].as_s.should eq("Test Org")
      result["subdomain"].as_s.should eq("test-lookup")
    end

    it "returns 404 for invalid subdomain" do
      response = client.get("/organizations/lookup?subdomain=non-existent")
      response.status_code.should eq(404)
    end
  end
end

# Helper methods
module OrganizationsSpecHelper
  extend self

  def create_test_user(email : String)
    user = App::Models::User.new
    user.name = "Test User"
    user.email = email
    user.password = "password123"
    user.save!
    user
  end

  def create_test_organization(name : String, owner : App::Models::User)
    org = App::Models::Organization.new
    org.name = name
    org.owner_id = owner.id
    org.save!

    # Add owner as admin
    org.add(owner, App::Permissions::Admin)

    org
  end

  def authenticated_request(client, user : App::Models::User, method : String, path : String)
    # Login to get session cookie
    login_result = client.post("/auth/login",
      body: "email=#{user.email}&password=password123",
      headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    )

    # Extract session cookie
    cookie = login_result.headers["Set-Cookie"]?
    raise "Login failed - no session cookie" unless cookie

    # Make authenticated request
    headers = HTTP::Headers{"Cookie" => cookie}

    case method.upcase
    when "GET"
      client.get(path, headers: headers)
    when "POST"
      client.post(path, headers: headers)
    when "PUT"
      client.put(path, headers: headers)
    when "DELETE"
      client.delete(path, headers: headers)
    else
      raise "Unsupported method: #{method}"
    end
  end
end

include OrganizationsSpecHelper
