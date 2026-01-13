class App::Health < App::Base
  base "/health"

  # Basic health check - returns 200 if app is running
  @[AC::Route::GET("/")]
  def index
    {status: "ok", timestamp: Time.utc.to_rfc3339}
  end

  # Detailed health check with database connectivity
  @[AC::Route::GET("/ready")]
  def ready
    db_ok = check_database

    status = db_ok ? "ok" : "degraded"
    http_status = db_ok ? HTTP::Status::OK : HTTP::Status::SERVICE_UNAVAILABLE

    response.status = http_status
    {
      status:    status,
      timestamp: Time.utc.to_rfc3339,
      checks:    {
        database: db_ok ? "ok" : "error",
      },
    }
  end

  # Liveness probe - just confirms app is running
  @[AC::Route::GET("/live")]
  def live
    {status: "ok"}
  end

  private def check_database : Bool
    PgORM::Database.connection do |db|
      db.query_one("SELECT 1", as: Int32) == 1
    end
  rescue
    false
  end
end
