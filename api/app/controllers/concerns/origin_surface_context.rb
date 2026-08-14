# Resolves the surface that produced an event from the current request.
#
# The signal already arrives: web/src/shared/lib/api.ts sends X-Platform on
# every call. All parsing and validation is delegated to
# Observability::Headers.platform, which truncates, checks the pattern and only
# then matches the canonical allow-list — a hostile value is DROPPED, never
# cleaned up and kept. See the security contract in that file.
#
# origin_surface answers "which surface produced THIS event". It is not a push
# capability and must never be inferred from a device token: a token proves the
# user CAN receive a push, not where they acted from.
module OriginSurfaceContext
  extend ActiveSupport::Concern

  # X-Platform's vocabulary (android|pwa|web|unknown) is about the client
  # runtime; origin_surface is about the producer, and also covers processes
  # that have no client at all (backend_scheduler, admin). pwa collapses into
  # web: both are the browser app.
  PLATFORM_TO_SURFACE = {
    "android" => "android",
    "web" => "web",
    "pwa" => "web"
  }.freeze

  private

  def origin_surface_from_request
    platform = Observability::Headers.platform(request.headers)
    PLATFORM_TO_SURFACE.fetch(platform.to_s, nil)
  end
end
