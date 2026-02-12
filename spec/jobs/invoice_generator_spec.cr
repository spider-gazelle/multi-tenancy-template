require "../spec_helper"
require "../../src/jobs/invoice_generator"

describe App::Jobs::InvoiceGenerator do
  it "generates invoice for due subscription" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    # Sub due now
    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc - 1.month,
      current_period_start: Time.utc - 1.month,
      current_period_end: Time.utc,
      next_invoice_at: Time.utc
    )

    App::Jobs::InvoiceGenerator.run

    sub.reload!
    sub.next_invoice_at.should be > Time.utc

    invoice = App::Models::Invoice.where(subscription_id: sub.id).first
    invoice.should_not be_nil
    invoice.status.should eq App::Models::Invoice::Status::Open
    invoice.amount_total.should eq 100_i64
  end

  it "skips cancelled subscriptions" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Cancelled,
      start_date: Time.utc - 1.month,
      current_period_start: Time.utc - 1.month,
      current_period_end: Time.utc,
      next_invoice_at: Time.utc
    )

    App::Jobs::InvoiceGenerator.run

    App::Models::Invoice.where(subscription_id: sub.id).to_a.size.should eq 0
  end

  it "skips suspended subscriptions" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Suspended,
      start_date: Time.utc - 1.month,
      current_period_start: Time.utc - 1.month,
      current_period_end: Time.utc,
      next_invoice_at: Time.utc
    )

    App::Jobs::InvoiceGenerator.run

    App::Models::Invoice.where(subscription_id: sub.id).to_a.size.should eq 0
  end

  it "does not create duplicate invoices on re-run (idempotency)" do
    org = create_organization
    user = create_user
    org.owner_id = user.id
    org.save!

    plan = App::Models::Plan.create!(name: "P1", billing_interval: "monthly", price: 100_i64)

    sub = App::Models::Subscription.create!(
      org_id: org.id, plan_id: plan.id, state: App::Models::Subscription::State::Active,
      start_date: Time.utc - 1.month,
      current_period_start: Time.utc - 1.month,
      current_period_end: Time.utc,
      next_invoice_at: Time.utc
    )

    App::Jobs::InvoiceGenerator.run
    App::Jobs::InvoiceGenerator.run

    App::Models::Invoice.where(subscription_id: sub.id).to_a.size.should eq 1
  end
end
