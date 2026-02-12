require "../models/organization"
require "../models/plan"
require "../models/subscription"
require "../models/invoice"
require "../models/payment"
require "./entitlement_service"
require "./payment_provider"
require "./notification_service"
require "./notification_providers/logger_provider"
require "./payment_providers/manual_provider"

module App::Services
  class BillingService
    Log = ::Log.for(self)

    @@notification_service : NotificationService = NotificationProviders::LoggerProvider.new
    @@payment_provider : PaymentProvider = PaymentProviders::ManualProvider.new

    def self.configure(payment_provider : PaymentProvider? = nil, notification_service : NotificationService? = nil)
      @@payment_provider = payment_provider if payment_provider
      @@notification_service = notification_service if notification_service
    end

    def self.payment_provider : PaymentProvider
      @@payment_provider
    end

    def self.create_subscription(org_id : UUID, plan_id : UUID, start_date : Time = Time.utc)
      org = App::Models::Organization.find!(org_id)
      plan = App::Models::Plan.find!(plan_id)

      existing = App::Models::Subscription.where("org_id = ? AND state IN ('Active', 'Suspended')", org.id).first?
      if existing
        raise "Organization already has an active or suspended subscription"
      end

      period_months = plan.billing_interval == "yearly" ? 12 : 1
      period_end = start_date + period_months.months

      sub = App::Models::Subscription.new(
        org_id: org.id,
        plan_id: plan.id,
        state: App::Models::Subscription::State::Active,
        start_date: start_date,
        current_period_start: start_date,
        current_period_end: period_end,
        next_invoice_at: start_date # Invoice immediately
      )
      sub.save!

      EntitlementService.recompute_snapshot(org)

      @@notification_service.send_subscription_change(org.owner.not_nil!, sub) if org.owner

      sub
    end

    def self.charge_invoice(invoice_id : UUID, token : String? = nil)
      invoice = App::Models::Invoice.find!(invoice_id)
      return nil if invoice.paid?

      provider_reference = @@payment_provider.charge(invoice, invoice.amount_total, token)
      record_payment(invoice.id, invoice.amount_total, @@payment_provider.provider_key, provider_reference)
    end

    def self.record_payment(invoice_id : UUID, amount : Int64, provider_key : String = "manual", provider_reference : String? = nil)
      invoice = App::Models::Invoice.find!(invoice_id)

      # Idempotency: if a provider_reference is given, check for duplicate
      if provider_reference
        existing = App::Models::Payment.where(invoice_id: invoice.id, provider_reference: provider_reference).first?
        return existing if existing
      end

      # Don't accept payments on already-paid invoices
      return nil if invoice.paid?

      # Create Payment Record
      payment = App::Models::Payment.new(
        invoice_id: invoice.id,
        amount: amount,
        paid_at: Time.utc,
        provider_key: provider_key,
        provider_reference: provider_reference
      )
      payment.save!

      # Check if invoice is fully paid
      total_paid = App::Models::Payment.where(invoice_id: invoice.id).sum("amount").to_i64

      if total_paid >= invoice.amount_total
        invoice.status = App::Models::Invoice::Status::Paid
        invoice.save!

        # Reactivate Subscription if needed
        sub = invoice.subscription
        if sub && sub.suspended?
          sub.state = App::Models::Subscription::State::Active
          sub.save!

          if org = sub.organization
            EntitlementService.recompute_snapshot(org)
          end

          if org && (owner = org.owner)
            @@notification_service.send_subscription_change(owner, sub)
          end
        end
      end

      payment
    end

    # Change plan for an org's subscription.
    def self.change_plan(org_id : UUID, new_plan_id : UUID)
      org = App::Models::Organization.find!(org_id)
      sub = App::Models::Subscription.where("org_id = ? AND state IN ('Active', 'Suspended')", org.id).first?
      raise "No subscription found for organization" unless sub
      raise "Cannot change plan on a cancelled subscription" if sub.cancelled?

      plan = App::Models::Plan.find!(new_plan_id)
      sub.plan_id = plan.id
      sub.save!

      # Recompute entitlements immediately so the new plan's services take effect
      EntitlementService.recompute_snapshot(org)

      if owner = org.owner
        @@notification_service.send_subscription_change(owner, sub)
      end

      sub
    end

    def self.cancel_subscription(id : UUID)
      # Try finding as subscription first, then fall back to org lookup
      sub = App::Models::Subscription.find?(id)
      unless sub
        org = App::Models::Organization.find!(id)
        sub = org.subscription
      end

      return unless sub

      sub.state = App::Models::Subscription::State::Cancelled
      sub.save!

      if org = sub.organization
        EntitlementService.recompute_snapshot(org)
        if owner = org.owner
          @@notification_service.send_subscription_change(owner, sub)
        end
      end
    end
  end
end
