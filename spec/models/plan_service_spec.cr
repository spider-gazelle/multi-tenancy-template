require "../spec_helper"

describe App::Models::Service do
  it "can create a service" do
    service = App::Models::Service.create!(
      name: "Test Service",
      entitlement_keys: ["test_key"]
    )
    service.name.should eq "Test Service"
    service.entitlement_keys.should eq ["test_key"]
  end
end

describe App::Models::Plan do
  it "can create a plan with services" do
    service = App::Models::Service.create!(name: "S1", entitlement_keys: ["k1"])

    plan = App::Models::Plan.create!(
      name: "Test Plan",
      billing_interval: "monthly",
      price: 1000_i64,
      currency: "USD",
      service_ids: [service.id]
    )

    plan.name.should eq "Test Plan"
    plan.services.size.should eq 1
    plan.services.first.name.should eq "S1"
  end
end
