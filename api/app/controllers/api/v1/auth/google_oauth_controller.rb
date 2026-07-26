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

        # Explicit allow-list: nothing else survives the hop. Anything a caller
        # appends (redirect_url, return_to, host, …) is discarded by construction
        # because the destination below is a literal relative path.
        ALLOWED_CONSENT_PARAMS = %i[terms_accepted privacy_accepted marketing_consent].freeze

        def web
          consent = ALLOWED_CONSENT_PARAMS.index_with { |key| User.explicit_true?(params[key]) }
          Rails.logger.info(
            "[GoogleOAuth] request_phase flow=web consent_present=" \
            "#{consent[:terms_accepted] && consent[:privacy_accepted]}"
          )

          redirect_to "/users/auth/google_oauth2?#{consent.to_query}",
                      status: :found,
                      allow_other_host: false
        end
      end
    end
  end
end
