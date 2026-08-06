# Server-side telemetry for the e-mail authentication flows.
#
# The whole point is the FIRST event: emitted as the request enters the action,
# it is the only proof that an e-mail login/signup actually reached the API. The
# client already says it tried (login_started / signup_started); until now
# nothing on the server agreed or disagreed, so a device that never reached the
# network was indistinguishable from one the server refused.
#
# PRIVACY: the params of these actions carry an e-mail and a password. Nothing
# from them is read here. The only client-supplied value that travels is
# X-Auth-Attempt-Id, which is opaque, random and validated like every other
# correlation header (Observability::Headers).
module EmailAuthTelemetry
  extend ActiveSupport::Concern

  private

  # Optional by contract: an absent or malformed header is not an error, the
  # request proceeds normally and the event simply carries no attempt id.
  def auth_attempt_id
    return @auth_attempt_id if defined?(@auth_attempt_id)

    @auth_attempt_id = Observability::Headers.identifier(
      request.headers, Observability::Headers::AUTH_ATTEMPT
    )
  end

  def emit_email_auth_started(intent)
    Observability::Events.email_auth_started(intent: intent, auth_attempt_id: auth_attempt_id)
  end

  def emit_email_auth_succeeded(intent, user: nil)
    Observability::Events.email_auth_succeeded(
      intent: intent, user: user, auth_attempt_id: auth_attempt_id
    )
  end

  def emit_email_auth_failed(intent, failure_category)
    Observability::Events.email_auth_failed(
      intent: intent, failure_category: failure_category, auth_attempt_id: auth_attempt_id
    )
  end
end
