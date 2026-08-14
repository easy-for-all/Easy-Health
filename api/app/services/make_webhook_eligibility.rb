class MakeWebhookEligibility
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAKE_WEBHOOK_ENABLED", "false"))
  end

  def self.webhook_url
    ENV["MAKE_WEBHOOK_URL"].to_s
  end

  def self.webhook_secret
    ENV["MAKE_WEBHOOK_SECRET"].to_s
  end

  def self.timeout_seconds
    ENV.fetch("MAKE_WEBHOOK_TIMEOUT_SECONDS", "10").to_i.clamp(1, 30)
  end

  def self.payload_mode
    mode = ENV.fetch("MAKE_WEBHOOK_PAYLOAD_MODE", "minimal").to_s
    %w[full minimal].include?(mode) ? mode : "minimal"
  end

  # Schema 2 is the canonical contract (explicit delivery.channels). The env var
  # stays as an override so production can roll back to schema 1 without a
  # redeploy; the default is 2 so a fresh environment is correct by default.
  def self.event_schema_version
    version = ENV.fetch("MAKE_EVENT_SCHEMA_VERSION", "2").to_s
    return version.to_i if %w[1 2].include?(version)

    raise ArgumentError, "MAKE_EVENT_SCHEMA_VERSION must be 1 or 2"
  end

  # The catalog decides which facts are orchestration events, so this list is
  # DERIVED from config/communication_events.yml and can never silently drop one
  # of them. MAKE_WEBHOOK_ENABLED remains the global kill switch, and
  # `enabled: false` in the YAML turns a single event off.
  def self.allowed_events
    CommunicationEvents.orchestration_event_names
  rescue CommunicationEvents::ConfigError
    []
  end

  # LEGACY. MAKE_WEBHOOK_ALLOWED_EVENTS used to be the allowlist; it is kept
  # only so smoke tests can fire an event that has no YAML entry yet. A name
  # sitting in an env var must never become a permanent business contract, so
  # in production it does nothing unless the escape hatch below is set — and it
  # always shows up in `allowlist_drift` as configuration still owed to the YAML.
  def self.legacy_env_events
    ENV.fetch("MAKE_WEBHOOK_ALLOWED_EVENTS", "")
       .split(",")
       .map(&:strip)
       .reject(&:blank?)
  end

  def self.legacy_escape_hatch_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAKE_WEBHOOK_ALLOW_LEGACY_ENV_EVENTS", "false"))
  end

  def self.legacy_env_event_allowed?(event_name)
    return false unless legacy_env_events.include?(event_name.to_s)
    return true unless Rails.env.production?

    legacy_escape_hatch_enabled?
  end

  def self.orchestration_event?(event_name)
    allowed_events.include?(event_name.to_s)
  end

  def self.event_allowed?(event_name)
    orchestration_event?(event_name) || legacy_env_event_allowed?(event_name)
  end

  # Reported by the admin. `env_only` is the real finding: an event being sent
  # (or wanting to be sent) without a catalog entry behind it.
  def self.allowlist_drift
    yaml = allowed_events
    env = legacy_env_events
    { env_only: env - yaml, yaml_only: yaml - env }
  end

  def self.configured?
    enabled? && webhook_url.present? && webhook_secret.present?
  end

  def self.eligible_for_new_event?(user:, event_name:, suppress_make_delivery: false)
    return false if suppress_make_delivery
    return false unless configured?
    return false unless account_valid?(user)

    if orchestration_event?(event_name)
      deliverable_channels(user, event_name).any?
    else
      # Legacy env-only event. Let it reach the delivery layer so it is reported
      # there with a precise reason (communication_event_disabled) instead of
      # being lumped in with "not an orchestration event"; it is never delivered
      # as a real communication because it has no channels.
      legacy_env_event_allowed?(event_name)
    end
  end

  def self.deliverable?(user_event)
    return false unless user_event
    return false if %w[accepted_by_make delivered].include?(user_event.make_delivery_status)

    eligible_for_new_event?(
      user: user_event.user,
      event_name: user_event.event_name,
      suppress_make_delivery: false
    )
  end

  def self.ineligibility_reason(user_event)
    return "make_webhook_disabled_or_unconfigured" unless configured?
    return "user_deleted_or_anonymized" unless account_valid?(user_event.user)
    return "event_not_orchestration" unless event_allowed?(user_event.event_name)

    if orchestration_event?(user_event.event_name) &&
       deliverable_channels(user_event.user, user_event.event_name).empty?
      return "no_deliverable_channel"
    end

    "not_deliverable"
  end

  # ── Hard gates, separated BY CHANNEL ────────────────────────────────────────
  #
  # The account gate applies to every channel: a deleted or anonymized user has
  # no communication of any kind. Everything else is channel-specific, because
  # mixing them is how a push event ends up blocked by an EMAIL rule.
  #
  # Push has no gate here on purpose. Whether the user has a token, has push
  # enabled, opted out of the category or is inside quiet hours is decided at
  # dispatch time (Make::PushDispatchRequest), where the answer is still true
  # when Make actually asks. Blocking the delivery of the FACT on those grounds
  # is exactly the confusion this architecture removes.
  def self.account_valid?(user)
    return false unless user
    return false if user.respond_to?(:deletion_requested_at) && user.deletion_requested_at.present?
    return false if user.respond_to?(:anonymized_at) && user.anonymized_at.present?

    true
  end

  # Marketing consent / unsubscribe / bounce are EMAIL compliance, unchanged
  # from the original rule. Make sends email directly, with no EasyHealth
  # callback able to re-apply the gate, so it must hold here.
  def self.email_consent_ok?(user)
    return false unless user
    return false if user.respond_to?(:marketing_consent?) && !user.marketing_consent?
    return false if user.respond_to?(:unsubscribed_at) && user.unsubscribed_at.present?
    return false if user.respond_to?(:email_bounced_at) && user.email_bounced_at.present?
    return false if user.email.blank?
    return false if user.email.end_with?("@easyhealth.invalid")

    true
  end

  def self.channel_allowed?(user, channel)
    case channel.to_s
    when "email" then email_consent_ok?(user)
    when "push"  then true
    else false
    end
  end

  # Candidate channels THIS user can actually be reached on. Persisted into
  # make_delivery_channels and sent as delivery.channels/candidate_channels, so
  # Make never receives a channel it is not allowed to use for this person.
  def self.deliverable_channels(user, event_name)
    CommunicationEvents.channels_for(event_name).select { |channel| channel_allowed?(user, channel) }
  rescue CommunicationEvents::ConfigError
    []
  end

  # DEPRECATED — kept because rake tasks and specs still call it. It is the old
  # all-channels-share-the-email-rule behaviour; new code must use
  # account_valid? plus deliverable_channels instead.
  def self.user_eligible_for_relationship?(user)
    account_valid?(user) && email_consent_ok?(user)
  end
end
