module Observability
  # Turns a request into a bounded route label such as
  # "/api/v1/workout_days/:id".
  #
  # This is the cardinality guarantee of the whole observability layer. A raw
  # path is unbounded: a scanner hitting 10_000 random URLs would otherwise
  # create 10_000 distinct label values in metrics and 10_000 distinct log
  # groupings. Here it produces exactly one extra value: "unmatched".
  #
  # Implementation note: ActionDispatch::Request#route_uri_pattern (Rails 8.1)
  # already gives us the matched pattern, so there is no need to re-run route
  # recognition. It is nil when nothing matched (404s, rack-attack blocks).
  module RouteNormalizer
    UNMATCHED = "unmatched".freeze
    OTHER     = "other".freeze
    ROOT      = "/".freeze
    MAX_LENGTH = 80

    module_function

    def call(request)
      raw = safe_pattern(request)
      return UNMATCHED if raw.blank?

      normalized = normalize(raw)
      return UNMATCHED if normalized.blank?

      known_routes.include?(normalized) ? normalized : OTHER
    rescue StandardError
      UNMATCHED
    end

    def normalize(pattern)
      pattern.to_s
             .sub(/\(\.:format\)\z/, "")
             .gsub(/\([^)]*\)/, "")
             .squeeze("/")
             .chomp("/")
             .presence
             &.slice(0, MAX_LENGTH) || ROOT
    end

    # Frozen allow-list of every route the app actually declares, built once.
    # Anything outside it collapses into OTHER.
    def known_routes
      @known_routes ||= build_known_routes
    end

    def reset!
      @known_routes = nil
    end

    def build_known_routes
      Rails.application.routes.routes.filter_map do |route|
        normalize(route.path.spec.to_s)
      end.to_set.freeze
    rescue StandardError
      Set.new.freeze
    end

    def safe_pattern(request)
      request.route_uri_pattern if request.respond_to?(:route_uri_pattern)
    end
  end
end
