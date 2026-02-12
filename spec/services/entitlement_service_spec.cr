require "../spec_helper"

describe App::Services::EntitlementService do
  it "returns false for unknown keys" do
    org = create_organization
    App::Services::EntitlementService.enabled?(org.id, "unknown").should be_false
  end

  it "correctly reflects snapshot data" do
    org = create_organization
    App::Models::EntitlementSnapshot.create!(
      org_id: org.id,
      enabled_service_keys: ["feature_a"],
      computed_at: Time.utc,
      reason: "manual"
    )

    App::Services::EntitlementService.enabled?(org.id, "feature_a").should be_true
    App::Services::EntitlementService.enabled?(org.id, "feature_b").should be_false
  end

  it "recompute_snapshot populates plan services for active subscription" do
    org = create_organization
    svc = App::Models::Service.create!(name: "SSO", entitlement_keys: ["sso", "saml"])
    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 1000_i64, service_ids: [svc.id])

    App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    App::Services::EntitlementService.recompute_snapshot(org)

    App::Services::EntitlementService.enabled?(org.id, "sso").should be_true
    App::Services::EntitlementService.enabled?(org.id, "saml").should be_true
  end

  it "recompute_snapshot gives minimal set for suspended subscription" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 1000_i64)

    App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Suspended,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    App::Services::EntitlementService.recompute_snapshot(org)

    App::Services::EntitlementService.enabled?(org.id, "billing_portal").should be_true
    App::Services::EntitlementService.enabled?(org.id, "read_only_export").should be_true
    App::Services::EntitlementService.enabled?(org.id, "admin_billing").should be_true
  end

  it "recompute_snapshot gives empty set when no subscription" do
    org = create_organization

    App::Services::EntitlementService.recompute_snapshot(org)

    App::Services::EntitlementService.list_enabled(org.id).should eq([] of String)
  end

  it "list_enabled returns correct keys" do
    org = create_organization
    App::Models::EntitlementSnapshot.create!(
      org_id: org.id,
      enabled_service_keys: ["feat_x", "feat_y"],
      computed_at: Time.utc,
      reason: "test"
    )

    result = App::Services::EntitlementService.list_enabled(org.id)
    result.should contain("feat_x")
    result.should contain("feat_y")
    result.size.should eq 2
  end
end
