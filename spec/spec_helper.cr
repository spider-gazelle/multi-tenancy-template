require "spec"

# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

# ensure the database is up to date
require "../src/constants"
require "micrate"
require "pg"
Micrate::DB.connection_url = App::PG_DATABASE_URL
Micrate::Cli.run_status
# Micrate::Cli.drop_database rescue nil
Micrate::Cli.run_up

# Your application config
require "../src/config"
