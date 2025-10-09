require "../spec_helper"

describe App::Models::Domain do
  org = App::Models::Organization.new
  domain = App::Models::Domain.new

  Spec.before_each do
    org = App::Models::Organization.new
    org.name = "Testing"
    org.save!

    domain = App::Models::Domain.new
  end

  it "should be able to create a domain" do
    domain.name = "Production"
    domain.domain = "Production.What.com"
    domain.organization = org
    domain.save!

    domain.domain.should eq "production.what.com"
    org.domains.map(&.id).should contain(domain.id)
  end

  it "should not allow two domains with the same domain name" do
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
