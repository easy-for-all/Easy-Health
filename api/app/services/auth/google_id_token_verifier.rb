module Auth
  # Verifies a Google ID token (JWT) locally against Google's published public
  # keys (JWKS), checking signature, issuer, audience and expiration. Used by the
  # native Android Google Sign-In flow, which sends the ID token straight to the
  # backend instead of going through the browser OmniAuth round-trip.
  class GoogleIdTokenVerifier
    class VerificationError < StandardError; end

    ISSUERS = [ "https://accounts.google.com", "accounts.google.com" ].freeze
    CERTS_URI = "https://www.googleapis.com/oauth2/v3/certs".freeze
    CERTS_CACHE_KEY = "google_oauth_jwks".freeze
    CERTS_TTL = 1.hour

    def self.verify!(id_token, audiences)
      new(audiences).verify!(id_token)
    end

    def initialize(audiences)
      @audiences = Array(audiences).compact.reject(&:blank?)
      raise VerificationError, "no audience configured (set GOOGLE_CLIENT_ID)" if @audiences.empty?
    end

    # Returns the verified claims hash (string keys) or raises VerificationError.
    def verify!(id_token)
      raise VerificationError, "missing id_token" if id_token.blank?

      payload, _header = JWT.decode(
        id_token,
        nil,
        true,
        algorithms: [ "RS256" ],
        jwks: jwks,
        iss: ISSUERS,
        verify_iss: true,
        aud: @audiences,
        verify_aud: true,
        verify_expiration: true
      )

      payload
    rescue JWT::DecodeError => e
      raise VerificationError, e.message
    end

    private

    def jwks
      Rails.cache.fetch(CERTS_CACHE_KEY, expires_in: CERTS_TTL) { fetch_jwks }
    end

    def fetch_jwks
      require "net/http"
      response = Net::HTTP.get_response(URI(CERTS_URI))
      unless response.is_a?(Net::HTTPSuccess)
        raise VerificationError, "failed to fetch Google certs (#{response.code})"
      end
      JSON.parse(response.body, symbolize_names: true)
    end
  end
end
