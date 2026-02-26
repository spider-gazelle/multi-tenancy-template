require "../models/invoice"
require "../models/subscription"
require "../services/entitlement_service"
require "../services/notification_service"
require "../services/notification_providers/logger_provider"

module App::Jobs
  class OverdueEnforcer
    @@notification_service : App::Services::NotificationService = App::Services::NotificationProviders::LoggerProvider.new

    def self.run
      now = Time.utc

      # Find Open Invoices
      App::Models::Invoice.where("status = 'Open'").each do |invoice|
        sub = invoice.subscription
        next unless sub

        # Calculate Overdue Threshold
        # due_date + grace_days
        cutoff_date = invoice.due_date + sub.cutoff_grace_days.days

        if now > cutoff_date
          suspend_subscription(sub, invoice)
        end
      end
    end

    def self.suspend_subscription(sub : App::Models::Subscription, invoice : App::Models::Invoice)
      return if sub.suspended? || sub.cancelled?

      sub.state = App::Models::Subscription::State::Suspended
      sub.save!

      if org = sub.organization
        App::Services::EntitlementService.recompute_snapshot(org)

        if owner = org.owner
          @@notification_service.send_overdue_alert(owner, invoice)
        end
      end
    end
  end
end
