require "../spec_helper"

describe App::Models::Subscription do
  it "defaults to active state" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.new(
      org_id: org.id,
      plan_id: plan.id,
      state: App::Models::Subscription::State::Active,
      start_date: Time.utc,
      current_period_start: Time.utc,
      current_period_end: Time.utc + 30.days,
      next_invoice_at: Time.utc
    )
    sub.save!
    sub.active?.should be_true
  end
end

describe App::Models::Invoice do
  it "calculates overdue correctly" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id,
      subscription_id: sub.id,
      period_start: Time.utc,
      period_end: Time.utc,
      issue_date: Time.utc,
      due_date: Time.utc - 1.day, # Past due
      amount_total: 100_i64,
      status: App::Models::Invoice::Status::Open
    )

    invoice.overdue?.should be_true
  end

  it "reports suspended? correctly" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Suspended,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )
    sub.suspended?.should be_true
    sub.active?.should be_false
    sub.cancelled?.should be_false
  end

  it "reports cancelled? correctly" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Cancelled,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )
    sub.cancelled?.should be_true
    sub.active?.should be_false
    sub.suspended?.should be_false
  end

  it "reports paid? correctly" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc + 14.days,
      amount_total: 100_i64, status: App::Models::Invoice::Status::Paid
    )

    invoice.paid?.should be_true
    invoice.open?.should be_false
    invoice.overdue?.should be_false
  end

  it "reports not overdue when not yet past due_date" do
    org = create_organization
    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc
    )

    invoice = App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc, due_date: Time.utc + 14.days,
      amount_total: 100_i64, status: App::Models::Invoice::Status::Open
    )

    invoice.overdue?.should be_false
    invoice.open?.should be_true
  end
end
