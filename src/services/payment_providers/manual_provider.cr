require "../payment_provider"

module App::Services::PaymentProviders
  class ManualProvider < App::Services::PaymentProvider
    Log = ::Log.for(self)

    def provider_key : String
      "manual"
    end

    # Manual payments don't have external customers — return a local reference.
    def create_customer(org : App::Models::Organization, email : String) : String
      Log.info { "Manual provider: customer record for org=#{org.id} email=#{email}" }
      "MANUAL-CUST-#{org.id}"
    end

    # For manual payments, token is an optional reference note (e.g. "Bank Transfer #123").
    def charge(invoice : App::Models::Invoice, amount : Int64, token : String?) : String
      Log.info { "Manual charge: invoice=#{invoice.id} amount=#{amount}" }
      token || "MANUAL-#{UUID.random}"
    end

    def refund(payment : App::Models::Payment) : Bool
      Log.info { "Manual refund: payment=#{payment.id}" }
      true
    end
  end
end
