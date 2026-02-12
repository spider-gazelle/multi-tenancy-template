require "../notification_service"
require "log"

module App::Services::NotificationProviders
  class LoggerProvider < App::Services::NotificationService
    Log = ::Log.for(self)

    def send_invoice(user : App::Models::User, invoice : App::Models::Invoice)
      Log.info { "Sending Invoice ##{invoice.id} to #{user.email} (Amount: #{invoice.amount_total})" }
    end

    def send_overdue_alert(user : App::Models::User, invoice : App::Models::Invoice)
      Log.warn { "Sending Overdue Alert for Invoice ##{invoice.id} to #{user.email}. Due: #{invoice.due_date}" }
    end

    def send_subscription_change(user : App::Models::User, subscription : App::Models::Subscription)
      Log.info { "Sending Subscription Change Notification to #{user.email}. New State: #{subscription.state}" }
    end
  end
end
