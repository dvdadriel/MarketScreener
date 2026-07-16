# Deep health endpoint for external uptime monitors. Inherits ActionController::Base
# directly to bypass the optional basic-auth and browser gating on
# ApplicationController, and returns 503 when degraded so a monitor actually trips.
class HealthController < ActionController::Base
  def show
    result = HealthCheck.run

    render json: {
      status: result.healthy? ? "ok" : "degraded",
      degraded: result.degraded,
      checks: result.checks,
      time: Time.current.iso8601
    }, status: result.healthy? ? :ok : :service_unavailable
  end
end
