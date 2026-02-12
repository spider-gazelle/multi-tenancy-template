require "../models/subscription"
require "../models/invoice"
require "../services/notification_service"
require "../services/notification_providers/logger_provider"

module App::Jobs
  class InvoiceGenerator
    @@notification_service : App::Services::NotificationService = App::Services::NotificationProviders::LoggerProvider.new

    def self.run
      now = Time.utc
      App::Models::Subscription.where("next_invoice_at <= ?", now).each do |sub|
        generate_invoice(sub)
      end
    end

    def self.generate_invoice(sub : App::Models::Subscription)
      return unless sub.active?

      period_start = sub.next_invoice_at
      period_months = sub.plan.billing_interval == "yearly" ? 12 : 1
      period_end = period_start + period_months.months

      existing = App::Models::Invoice.where(
        subscription_id: sub.id,
        period_start: period_start,
      ).first?
      return if existing

      invoice = App::Models::Invoice.new(
        org_id: sub.org_id,
        subscription_id: sub.id,
        period_start: period_start,
        period_end: period_end,
        issue_date: Time.utc,
        due_date: Time.utc + sub.payment_terms_days.days,
        amount_total: sub.plan.price,
        status: App::Models::Invoice::Status::Open
      )
      invoice.save!

      sub.current_period_start = period_start
      sub.current_period_end = period_end
      sub.next_invoice_at = period_end
      sub.save!

      if org = sub.organization
        if owner = org.owner
          @@notification_service.send_invoice(owner, invoice)
        end
      end
    end
  end
end
