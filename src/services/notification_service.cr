module App::Services
  abstract class NotificationService
    abstract def send_invoice(user : App::Models::User, invoice : App::Models::Invoice)
    abstract def send_overdue_alert(user : App::Models::User, invoice : App::Models::Invoice)
    abstract def send_subscription_change(user : App::Models::User, subscription : App::Models::Subscription)
  end
end
