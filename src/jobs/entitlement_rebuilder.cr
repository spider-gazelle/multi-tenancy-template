require "../models/organization"
require "../services/entitlement_service"

module App::Jobs
  class EntitlementRebuilder
    def self.run
      App::Models::Organization.all.each do |org|
        App::Services::EntitlementService.recompute_snapshot(org)
      end
    end
  end
end
