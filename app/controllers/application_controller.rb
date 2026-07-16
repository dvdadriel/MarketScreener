class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Optional HTTP basic auth — enabled only when both env vars are present, so
  # exposing the dashboard beyond localhost (e.g. on the LAN for mobile) doesn't
  # leave signals/P&L open. Left off by default for local-only use.
  RADAR_HTTP_USER = ENV["RADAR_HTTP_USER"].freeze
  RADAR_HTTP_PASSWORD = ENV["RADAR_HTTP_PASSWORD"].freeze

  if RADAR_HTTP_USER.present? && RADAR_HTTP_PASSWORD.present?
    http_basic_authenticate_with name: RADAR_HTTP_USER, password: RADAR_HTTP_PASSWORD
  end
end
