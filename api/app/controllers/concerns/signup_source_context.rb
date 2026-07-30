# Resolves the platform OBSERVED on a signup request, for users.signup_source.
#
# The signal already arrives today: web/src/shared/lib/api.ts sends X-Platform on
# every request, carrying the robust detection from analytics/context.ts
# (android|pwa|web|unknown). Nothing in the client had to change for the
# email/password and native Google flows — the header was simply never read by
# the controllers that create a User.
#
# All normalization is delegated to Observability::Headers.platform, which
# truncates, validates the pattern, and only then checks the canonical
# allow-list. A hostile or unrecognized value is DROPPED ("unknown"), never
# "cleaned up and kept" — see the security contract in that file.
module SignupSourceContext
  extend ActiveSupport::Concern

  private

  def signup_source_from_request
    Observability::Headers.platform(request.headers) || "unknown"
  end

  # Same contract for a value that arrived over some other transport than the
  # header. The Google OAuth callback is a browser navigation coming back from
  # Google and carries no custom headers, so the platform travels in
  # omniauth.params instead. Passing a plain Hash reuses the one parser rather
  # than duplicating the allow-list here.
  def signup_source_from_value(value)
    Observability::Headers.platform(Observability::Headers::PLATFORM => value) || "unknown"
  end
end
