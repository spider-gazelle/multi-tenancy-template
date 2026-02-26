require "../spec_helper"
require "../../src/jobs/overdue_enforcer"

describe App::Jobs::OverdueEnforcer do
  it "suspends subscription when invoice is overdue" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc,
      cutoff_grace_days: 7
    )

    App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc - 20.days,
      due_date: Time.utc - 8.days,
      amount_total: 100_i64,
      status: App::Models::Invoice::Status::Open
    )

    App::Jobs::OverdueEnforcer.run

    sub.reload!.state.should eq App::Models::Subscription::State::Suspended
  end

  it "does not suspend when still within grace period" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc,
      cutoff_grace_days: 7
    )

    App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc - 10.days,
      due_date: Time.utc - 3.days,
      amount_total: 100_i64,
      status: App::Models::Invoice::Status::Open
    )

    App::Jobs::OverdueEnforcer.run

    sub.reload!.state.should eq App::Models::Subscription::State::Active
  end

  it "skips already-suspended subscriptions" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Suspended,
      start_date: Time.utc, current_period_start: Time.utc, current_period_end: Time.utc, next_invoice_at: Time.utc,
      cutoff_grace_days: 7
    )

    App::Models::Invoice.create!(
      org_id: org.id, subscription_id: sub.id, period_start: Time.utc, period_end: Time.utc,
      issue_date: Time.utc - 20.days,
      due_date: Time.utc - 8.days,
      amount_total: 100_i64,
      status: App::Models::Invoice::Status::Open
    )

    App::Jobs::OverdueEnforcer.run

    sub.reload!.state.should eq App::Models::Subscription::State::Suspended
  end
end
