require "../spec_helper"

describe App::Models::Domain do
  Spec.before_each do
    App::Models::Organization.clear
    App::Models::Domain.clear
  end

  it "should be able to create a domain" do
    org = App::Models::Organization.new(name: "Testing")
    org.save!

    domain = App::Models::Domain.new
    domain.name = "Production"
    domain.domain = "Production.What.com"
    domain.organization = org
    domain.save!

    domain.domain.should eq "production.what.com"
    org.domains.map(&.id).should contain(domain.id)
  end

  it "should not allow two domains with the same domain name" do
    org = App::Models::Organization.new(name: "Testing")
    org.save!

    domain = App::Models::Domain.new
    domain.name = "Production"
    domain.domain = "Production.What.com"
    domain.organization = org
    domain.save!

    domain2 = App::Models::Domain.new
    domain2.name = "Dev"
    domain2.domain = "Production.What.com"
    domain2.organization = org

    expect_raises(PgORM::Error::RecordInvalid) { domain2.save! }
  end
end
