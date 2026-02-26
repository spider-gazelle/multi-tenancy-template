require "micrate"
require "../src/config"

Micrate::DB.connection_url = App::PG_DATABASE_URL
Micrate::Cli.run_up

puts "Seeding Services..."

# Helper to find or create service
def ensure_service(name : String, description : String)
  service = App::Models::Service.find_by?(name: name)
  unless service
    service = App::Models::Service.new(
      name: name,
      description: description,
      entitlement_keys: [] of String
    )
    service.save!
    puts "Created Service: #{name}"
  else
    puts "Service exists: #{name}"
  end
  service
end

s_users = ensure_service("unlimited_users", "Add unlimited users to your organization")
s_audit = ensure_service("audit_logs", "Access to audit logs")
s_sso = ensure_service("sso", "Single Sign-On (SAML/OIDC)")
s_api = ensure_service("api_access", "Access to API")

puts "Seeding Plans..."

def ensure_plan(name : String, price : Int64, currency : String, billing_interval : String, service_ids : Array(UUID))
  plan = App::Models::Plan.find_by?(name: name)
  unless plan
    plan = App::Models::Plan.new(
      name: name,
      price: price,
      currency: currency,
      billing_interval: billing_interval,
      service_ids: service_ids
    )
    plan.save!
    puts "Created Plan: #{name}"
  else
    puts "Plan exists: #{name}"
  end
  plan
end

# Free Plan
ensure_plan("Free", 0_i64, "USD", "monthly", [] of UUID)

# Pro Plan
ensure_plan("Pro", 2900_i64, "USD", "monthly", [s_users.id, s_api.id])

# Enterprise Plan
ensure_plan("Enterprise", 9900_i64, "USD", "monthly", [s_users.id, s_api.id, s_audit.id, s_sso.id])

puts "Seeding complete."
