require "../spec_helper"

describe App::Domains do
  client = AC::SpecHelper.client

  Spec.before_each do
    # Clean up test data
    App::Models::Domain.clear
    App::Models::OrganizationUser.clear
    App::Models::Organization.clear
    App::Models::User.clear
  end

  describe "GET /organizations/:id/domains" do
    it "should return organization domains" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      domain1 = create_test_domain("example.com", "Example", org)
      domain2 = create_test_domain("test.com", "Test", org)

      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "2"
      result.headers["Content-Range"].should eq "domains 0-1/2"

      domains = Array(App::Models::Domain).from_json(result.body)
      domains.size.should eq 2
    end

    it "should paginate domain results" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      5.times { |i| create_test_domain("domain#{i}.com", "Domain #{i}", org) }

      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains?limit=2&offset=0")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "5"
      result.headers["Content-Range"].should eq "domains 0-1/5"
      result.headers["Link"]?.should_not be_nil

      domains = Array(App::Models::Domain).from_json(result.body)
      domains.size.should eq 2
    end

    it "should search domains by domain name" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      create_test_domain("api.example.com", "API", org)
      create_test_domain("www.example.com", "Website", org)
      create_test_domain("test.com", "Test", org)

      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains?q=example&fields=domain,name")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "2"

      domains = Array(App::Models::Domain).from_json(result.body)
      domains.size.should eq 2
      domains.all? { |d| d.domain.includes?("example") }.should be_true
    end

    it "should search domains in specific fields" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)

      domain1 = create_test_domain("api.example.com", "API Server", org)
      domain1.description = "Production API"
      domain1.save!

      domain2 = create_test_domain("test.com", "Test Domain", org)
      domain2.description = "API testing environment"
      domain2.save!

      # Search only in domain field
      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains?q=api&fields=domain")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"

      domains = Array(App::Models::Domain).from_json(result.body)
      domains.size.should eq 1
      domains[0].domain.should eq "api.example.com"
    end

    it "should sort domains" do
      user = create_test_user("test@example.com")
      org = create_test_organization("Tech Corp", user)
      create_test_domain("zebra.com", "Zebra", org)
      create_test_domain("apple.com", "Apple", org)
      create_test_domain("microsoft.com", "Microsoft", org)

      # Sort by domain ascending
      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains?sort=domain&order=asc")

      domains = Array(App::Models::Domain).from_json(result.body)
      domains[0].domain.should eq "apple.com"
      domains[2].domain.should eq "zebra.com"

      # Sort by name descending
      result = authenticated_request(client, user, "GET", "/organizations/#{org.id}/domains?sort=name&order=desc")

      domains = Array(App::Models::Domain).from_json(result.body)
      domains[0].name.should eq "Zebra"
      domains[2].name.should eq "Apple"
    end

    it "should only return domains for the specified organization" do
      user = create_test_user("test@example.com")
      org1 = create_test_organization("Org 1", user)
      org2 = create_test_organization("Org 2", user)

      domain1 = create_test_domain("org1.com", "Org 1 Domain", org1)
      domain2 = create_test_domain("org2.com", "Org 2 Domain", org2)

      result = authenticated_request(client, user, "GET", "/organizations/#{org1.id}/domains")

      result.status_code.should eq 200
      result.headers["X-Total-Count"].should eq "1"

      domains = Array(App::Models::Domain).from_json(result.body)
      domains.size.should eq 1
      domains[0].domain.should eq "org1.com"
    end

    it "should require authentication" do
      result = client.get("/organizations/123/domains")
      result.status_code.should eq 401
    end

    it "should require organization access" do
      user1 = create_test_user("user1@example.com")
      user2 = create_test_user("user2@example.com")
      org = create_test_organization("Private Org", user1)

      # user2 tries to access user1's organization
      result = authenticated_request(client, user2, "GET", "/organizations/#{org.id}/domains")
      result.status_code.should eq 403
    end
  end
end

# Helper methods
module DomainsSpecHelper
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

  def create_test_domain(domain : String, name : String, org : App::Models::Organization)
    d = App::Models::Domain.new
    d.domain = domain
    d.name = name
    d.organization_id = org.id
    d.save!
    d
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

include DomainsSpecHelper
