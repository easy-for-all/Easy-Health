module Observability
  # Deterministic identity for "the same problem".
  #
  # Two detections with the same fingerprint collapse into one incident. Getting
  # this wrong is expensive in both directions: too coarse and a native-only
  # outage hides inside a web incident; too fine and one bad night produces
  # hundreds of rows nobody reads.
  #
  # THE RULE THAT MATTERS: dimensions are restricted to a per-check allow-list of
  # low-cardinality keys. A user id or installation ref in here would mint one
  # incident per affected user — turning an outage into an unusable wall of
  # duplicates, and putting identifiers into a notification payload besides.
  module Fingerprint
    ALLOWED_DIMENSIONS = %w[build_group auth_flow heartbeat_key category integration job platform route alertname service].freeze

    module_function

    def call(source:, check_key:, dimensions: {}, environment: nil)
      material = [
        source.to_s,
        check_key.to_s,
        environment.presence || Rails.env.to_s,
        canonical_dimensions(dimensions).to_json
      ].join("|")

      Digest::SHA256.hexdigest(material)[0, 32]
    end

    # Sorted so key order cannot change the hash, filtered so only the
    # allow-list survives, stringified so 1 and "1" agree.
    def canonical_dimensions(dimensions)
      (dimensions || {})
        .transform_keys(&:to_s)
        .slice(*ALLOWED_DIMENSIONS)
        .transform_values(&:to_s)
        .sort
        .to_h
    end
  end
end
