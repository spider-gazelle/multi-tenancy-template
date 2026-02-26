require "../spec_helper"

describe App::Services::BillingService do
  it "creates a subscription and entitlement snapshot" do
    org = create_organization("Test Org")
    user = create_user("test@example.com")
    org.owner_id = user.id
    org.save!

    sso = App::Models::Service.create!(name: "SSO", entitlement_keys: ["sso"])
    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64, currency: "USD", service_ids: [sso.id])

    sub = App::Services::BillingService.create_subscription(org.id, plan.id)

    sub.state.should eq App::Models::Subscription::State::Active

    # Check entitlements
    App::Services::EntitlementService.enabled?(org.id, "sso").should be_true
  end

  it "records payment and reactivates suspended subscription" do
    org = create_organization("Test Org 2")
    user = create_user("test2@example.com")
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Suspended,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc, amount_total: 5000_i64, status: App::Models::Invoice::Status::Open
    )

    # Record full payment
    App::Services::BillingService.record_payment(invoice.id, 5000_i64, "manual")

    invoice.reload!.status.should eq App::Models::Invoice::Status::Paid
    sub.reload!.state.should eq App::Models::Subscription::State::Active
  end

  it "rejects duplicate active subscription for same org" do
    org = create_organization("Dup Org")
    user = create_user("dup@example.com")
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)
    App::Services::BillingService.create_subscription(org.id, plan.id)

    expect_raises(Exception, "Organization already has an active or suspended subscription") do
      App::Services::BillingService.create_subscription(org.id, plan.id)
    end
  end

  it "change_plan updates plan and recomputes entitlements" do
    org = create_organization("Change Org")
    user = create_user("change@example.com")
    org.owner_id = user.id
    org.save!

    svc_a = App::Models::Service.create!(name: "A", entitlement_keys: ["feat_a"])
    svc_b = App::Models::Service.create!(name: "B", entitlement_keys: ["feat_b"])
    plan_a = App::Models::Plan.create!(name: "PlanA", billing_interval: "monthly", price: 1000_i64, service_ids: [svc_a.id])
    plan_b = App::Models::Plan.create!(name: "PlanB", billing_interval: "monthly", price: 2000_i64, service_ids: [svc_b.id])

    App::Services::BillingService.create_subscription(org.id, plan_a.id)
    App::Services::EntitlementService.enabled?(org.id, "feat_a").should be_true

    sub = App::Services::BillingService.change_plan(org.id, plan_b.id)
    sub.plan_id.should eq plan_b.id

    App::Services::EntitlementService.enabled?(org.id, "feat_b").should be_true
    App::Services::EntitlementService.enabled?(org.id, "feat_a").should be_false
  end

  it "change_plan raises when no active subscription exists" do
    org = create_organization("No Sub Org")

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)

    expect_raises(Exception, "No subscription found for organization") do
      App::Services::BillingService.change_plan(org.id, plan.id)
    end
  end

  it "cancel_subscription sets state to Cancelled and clears entitlements" do
    org = create_organization("Cancel Org")
    user = create_user("cancel@example.com")
    org.owner_id = user.id
    org.save!

    svc = App::Models::Service.create!(name: "Svc", entitlement_keys: ["feat"])
    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64, service_ids: [svc.id])

    sub = App::Services::BillingService.create_subscription(org.id, plan.id)
    App::Services::EntitlementService.enabled?(org.id, "feat").should be_true

    App::Services::BillingService.cancel_subscription(sub.id)

    sub.reload!
    sub.state.should eq App::Models::Subscription::State::Cancelled
    App::Services::EntitlementService.enabled?(org.id, "feat").should be_false
  end

  it "record_payment is idempotent on duplicate provider_reference" do
    org = create_organization("Idemp Org")
    user = create_user("idemp@example.com")
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc, amount_total: 5000_i64, status: App::Models::Invoice::Status::Open
    )

    p1 = App::Services::BillingService.record_payment(invoice.id, 5000_i64, "stripe", "ch_abc123")
    p2 = App::Services::BillingService.record_payment(invoice.id, 5000_i64, "stripe", "ch_abc123")

    p1.should_not be_nil
    p2.should_not be_nil
    p1.not_nil!.id.should eq p2.not_nil!.id

    # Only one payment record should exist
    App::Models::Payment.where(invoice_id: invoice.id).to_a.size.should eq 1
  end

  it "record_payment returns nil on already-paid invoice" do
    org = create_organization("Paid Org")
    user = create_user("paid@example.com")
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc, amount_total: 5000_i64, status: App::Models::Invoice::Status::Paid
    )

    result = App::Services::BillingService.record_payment(invoice.id, 5000_i64, "manual")
    result.should be_nil
  end

  it "charge_invoice delegates to provider and records payment" do
    org = create_organization("Charge Org")
    user = create_user("charge@example.com")
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "Pro", billing_interval: "monthly", price: 5000_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc, amount_total: 5000_i64, status: App::Models::Invoice::Status::Open
    )

    payment = App::Services::BillingService.charge_invoice(invoice.id)
    payment.should_not be_nil
    payment.not_nil!.amount.should eq 5000_i64
    payment.not_nil!.provider_key.should eq "manual"

    invoice.reload!.status.should eq App::Models::Invoice::Status::Paid
  end
end
