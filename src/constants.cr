require "action-controller/logger"
require "dotenv"

module App
  Dotenv.load if File.exists?(".env")

  NAME = "Spider-Gazelle"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  Log         = ::Log.for(NAME)
  LOG_BACKEND = ActionController.default_backend

  ENVIRONMENT   = ENV["SG_ENV"]? || "development"
  IS_PRODUCTION = ENVIRONMENT == "production"

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  STATIC_FILE_PATH = ENV["PUBLIC_WWW_PATH"]? || "./www"

  COOKIE_SESSION_KEY    = ENV["COOKIE_SESSION_KEY"]? || "_spider_gazelle_"
  COOKIE_SESSION_SECRET = ENV["COOKIE_SESSION_SECRET"]? || "4f74c0b358d5bab4000dd3c75465dc2c"

  PG_DATABASE_URL = ENV["PG_DATABASE_URL"]

  # JWT/OAuth2 Configuration
  JWT_SECRET = ENV["JWT_SECRET"]? || raise "JWT_SECRET environment variable required for OAuth2/OIDC"
  JWT_ISSUER = ENV["JWT_ISSUER"]? || NAME

  # Application URLs
  APP_BASE_URL = ENV["APP_BASE_URL"]? || "http://localhost:3000"

  # OAuth Provider Credentials
  GOOGLE_CLIENT_ID     = ENV["GOOGLE_CLIENT_ID"]? || ""
  GOOGLE_CLIENT_SECRET = ENV["GOOGLE_CLIENT_SECRET"]? || ""

  MICROSOFT_CLIENT_ID     = ENV["MICROSOFT_CLIENT_ID"]? || ""
  MICROSOFT_CLIENT_SECRET = ENV["MICROSOFT_CLIENT_SECRET"]? || ""
  MICROSOFT_TENANT_ID     = ENV["MICROSOFT_TENANT_ID"]? || "common"

  # Job Scheduling
  # Set to "true" to disable in-process Tasker cron jobs (use when running jobs externally via K8s CronJobs)
  DISABLE_TASKER = ENV["DISABLE_TASKER"]? == "true"

  # Cron schedules for in-process jobs (standard cron syntax)
  CRON_INVOICE_GENERATOR     = ENV["CRON_INVOICE_GENERATOR"]? || "0 0 * * *"     # Daily at midnight
  CRON_OVERDUE_ENFORCER      = ENV["CRON_OVERDUE_ENFORCER"]? || "0 1 * * *"      # Daily at 1am
  CRON_ENTITLEMENT_REBUILDER = ENV["CRON_ENTITLEMENT_REBUILDER"]? || "0 2 * * *" # Daily at 2am

  def self.running_in_production?
    IS_PRODUCTION
  end
end
