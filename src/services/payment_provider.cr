module App::Services
  abstract class PaymentProvider
    # Provider identifier (e.g. "stripe", "manual")
    abstract def provider_key : String

    # Create a customer record on the provider side.
    # Returns the provider's customer ID for future charges.
    abstract def create_customer(org : App::Models::Organization, email : String) : String

    # Charge a payment method for the given invoice.
    # `token` is provider-specific (e.g. card token, payment method ID).
    # Returns the provider's charge/payment reference ID.
    abstract def charge(invoice : App::Models::Invoice, amount : Int64, token : String?) : String

    # Refund a previously captured payment.
    # Returns true if the refund was accepted by the provider.
    abstract def refund(payment : App::Models::Payment) : Bool
  end
end
