module Api
  module V1
    module Auth
      # Entry point of the web (browser) Google flow. This used to be a bare
      # `redirect("/users/auth/google_oauth2")` in routes.rb, but Rails'
      # PathRedirect builds the destination from the literal string only and
      # never reattaches `request.query_string` — so the consent flags the
      # sign-up screen appends were silently dropped before OmniAuth ever saw
      # them, and no brand-new Google account could be created on the web.
      #
      # Forwarding them here puts them back in the request phase, where OmniAuth
      # stores `request.GET` in the session and hands it back to the callback as
      # `omniauth.params` (see OmniauthCallbacksController#oauth_consent_params).
      class GoogleOauthController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        # Explicit allow-list: only these and `platform` survive the hop (see
        # #web). Anything else a caller appends (redirect_url, return_to, host, …)
        # is discarded by construction because the destination below is a literal
        # relative path.
        ALLOWED_CONSENT_PARAMS = %i[terms_accepted privacy_accepted marketing_consent].freeze

        def web
          consent = ALLOWED_CONSENT_PARAMS.index_with { |key| User.explicit_true?(params[key]) }
          # The platform rides the SAME channel as the consent flags because the
          # callback is a browser navigation coming back from Google and has no
          # X-Platform header — this is the only way the signup origin reaches the
          # server on this flow. It cannot join ALLOWED_CONSENT_PARAMS above:
          # that hash runs every key through explicit_true?, which would turn
          # "android" into false.
          #
          # Validated against the canonical allow-list BEFORE the hop, and
          # .compact keeps an absent platform absent: with no platform in, the
          # outgoing query stays byte-identical to what it was before this change.
          forwarded = consent.merge(platform: allowed_platform).compact

          Rails.logger.info(
            "[GoogleOAuth] request_phase flow=web consent_present=" \
            "#{consent[:terms_accepted] && consent[:privacy_accepted]} " \
            "platform=#{forwarded[:platform] || 'absent'}"
          )

          redirect_to "/users/auth/google_oauth2?#{forwarded.to_query}",
                      status: :found,
                      allow_other_host: false
        end

        private

        def allowed_platform
          Observability::Headers.platform(Observability::Headers::PLATFORM => params[:platform])
        end
      end
    end
  end
end
