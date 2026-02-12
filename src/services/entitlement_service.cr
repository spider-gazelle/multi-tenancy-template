require "../models/organization"
require "../models/entitlement_snapshot"
require "../models/plan"
require "../models/service"

module App::Services
  class EntitlementService
    SUSPENDED_FEATURES = ["billing_portal", "read_only_export", "admin_billing"]

    # Recompute snapshot when Plan changes
    def self.recompute_snapshot(org : Models::Organization)
      # Find active/suspended subscription (skip cancelled)
      subscription = Models::Subscription.where("org_id = ? AND state IN ('Active', 'Suspended')", org.id).first?

      snapshot = Models::EntitlementSnapshot.find_by?(org_id: org.id) ||
                 Models::EntitlementSnapshot.new(org_id: org.id)

      # If no subscription, no entitlements
      if subscription.nil?
        snapshot.enabled_service_keys = [] of String
        snapshot.reason = "no_subscription"
        snapshot.computed_at = Time.utc
        snapshot.save!
        return
      end

      case
      when subscription.active?
        plan = Models::Plan.find_by?(id: subscription.plan_id)
        services = plan ? plan.services : [] of Models::Service
        features = services.flat_map(&.entitlement_keys).uniq
        snapshot.enabled_service_keys = features
        snapshot.reason = "subscription_active:#{plan.try(&.name)}"
      when subscription.suspended?
        snapshot.enabled_service_keys = SUSPENDED_FEATURES.dup
        snapshot.reason = "subscription_suspended"
      when subscription.cancelled?
        snapshot.enabled_service_keys = [] of String
        snapshot.reason = "subscription_cancelled"
      else
        snapshot.enabled_service_keys = [] of String
        snapshot.reason = "unknown_state:#{subscription.state}"
      end

      snapshot.computed_at = Time.utc
      snapshot.save!
    end

    # Check boolean feature entitlement
    def self.has_feature?(org : Models::Organization, feature_key : String) : Bool
      # Use snapshot for fast read
      snapshot = Models::EntitlementSnapshot.find_by?(org_id: org.id)
      return false unless snapshot

      snapshot.enabled_service_keys.includes?(feature_key)
    end

    def self.enabled?(org_id : UUID, feature_key : String) : Bool
      # We could cache this in Redis later. For now, DB read is fast enough.
      snapshot = Models::EntitlementSnapshot.find_by?(org_id: org_id)
      return false unless snapshot

      snapshot.enabled_service_keys.includes?(feature_key)
    end

    def self.list_enabled(org_id : UUID) : Array(String)
      snapshot = Models::EntitlementSnapshot.find_by?(org_id: org_id)
      return [] of String unless snapshot
      snapshot.enabled_service_keys
    end
  end
end
