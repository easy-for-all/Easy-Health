module AppInstallations
  # THE single writer of app_installations.user_id.
  #
  # Every path that links an installation to a user goes through here, so the
  # semantics (idempotency, conflict handling, attempt bookkeeping) exist once
  # instead of being re-derived by each caller. A spec enforces that nothing else
  # in app/ writes user_id on this table.
  #
  # Contract:
  #   * Never raises to the caller. Authentication must not depend on tracking.
  #   * Never steals an installation already owned by another user.
  #   * Never gates on build_number. The Android shell loads a remote web bundle,
  #     so build tells us nothing about whether the header can arrive.
  #   * Emits structured logs only. Request-level analytics (Observability::Events)
  #     stay with the caller, which knows the request context; this service also
  #     runs from rake and must not fabricate request events.
  class LinkToUser
    STATUSES = %i[
      linked already_linked conflict invalid_input
      validation_failed not_found unexpected_error
    ].freeze

    # Closed vocabulary. A failure_code reaches a log field and the
    # last_link_failure_code column, so it must never carry an exception message
    # or any other unbounded string.
    FAILURE_CODES = %w[
      user_conflict invalid_input validation_failed record_not_unique
      stale_object statement_invalid unexpected_error installation_not_found
    ].freeze

    # These log lines share their event names with Observability::Events, which
    # the callers emit for the same link. Both land in the log sink, so without a
    # producer field a log-based count of installation_link_succeeded would count
    # one link twice. The durable sink (Analytics::ServerEvents) is written only
    # by the caller, once. Filter by producer to count service traces.
    PRODUCER = "link_to_user".freeze

    # An already-linked installation only rewrites last_authenticated_at once an
    # hour: without this every authenticated app request would be an UPDATE.
    TOUCH_INTERVAL = 1.hour

    # A permanent outcome is deterministic: repeating the same attempt with the
    # same inputs cannot produce a different answer, so retrying it only costs a
    # row lock, an UPDATE and an analytics row per request. Everything else is
    # legitimately recoverable — not_found is fixed by a later register,
    # validation/statement/unexpected failures by the next attempt — and keeps
    # being retried.
    PERMANENT_STATUSES = %i[conflict invalid_input].freeze

    Result = Struct.new(:success, :status, :installation, :failure_code, keyword_init: true) do
      def linked?
        status == :linked
      end

      def permanent?
        !success && PERMANENT_STATUSES.include?(status)
      end

      def retryable?
        !success && !permanent?
      end
    end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # For callers that could not even find an installation, so the whole flow
    # speaks one status vocabulary.
    def self.not_found
      Result.new(success: false, status: :not_found, installation: nil, failure_code: "installation_not_found")
    end

    def initialize(installation:, user:, source: nil, runtime_context: nil, build_number: nil)
      @installation = installation
      @user = user
      @source = source.presence || "unknown"
      @runtime_context = runtime_context.presence
      @build_number = build_number.presence
    end

    def call
      return invalid_input unless linkable_input?

      # Fast path: the overwhelmingly common case is an authenticated request on
      # an installation that is already linked. It must not count as an attempt,
      # must not touch linked_at and must not log at info level.
      return already_linked if @installation.user_id == @user.id

      # Second fast path: a conflict we have already decided and persisted.
      # Reconciliation is an after_action on every authenticated request, so
      # without this an installation owned by someone else costs a row lock, an
      # UPDATE and a warn line on EVERY request the app makes, forever. The
      # protection is unchanged — the installation still belongs to its owner;
      # we simply stop re-deciding a question whose answer cannot change.
      return repeat_conflict if known_conflict?

      log(:installation_link_started)
      attempt_link
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError => e
      handle_failure(:validation_failed, failure_code_for(e))
    rescue ActiveRecord::StatementInvalid => e
      report(e)
      handle_failure(:unexpected_error, "statement_invalid")
    rescue StandardError => e
      report(e)
      handle_failure(:unexpected_error, "unexpected_error")
    end

    private

    def linkable_input?
      !@installation.nil? && !@user.nil? && @installation.persisted?
    end

    # Already owned by someone else AND already recorded as such. Deliberately
    # reuses last_link_failure_code instead of adding a "gave up" column: that
    # column is already cleared when a link finally succeeds, so the legitimate
    # owner returning to the device is never blocked by this guard.
    #
    # The first conflict does NOT match (the code is still nil), so it goes the
    # full path: it takes the lock, counts the attempt and logs at warn.
    def known_conflict?
      @installation.user_id.present? &&
        @installation.user_id != @user.id &&
        @installation.last_link_failure_code == "user_conflict"
    end

    # No lock, no UPDATE, no counter, no warn — only the answer. Kept at debug so
    # a per-request trace is still available when someone goes looking.
    def repeat_conflict
      log(:installation_link_conflict, level: :debug, status: :conflict,
                                       failure_code: "user_conflict", repeat: true)
      failure(:conflict, "user_conflict")
    end

    def attempt_link
      status = nil

      @installation.with_lock do
        # Re-decide inside the lock: two concurrent requests both saw user_id nil.
        if @installation.user_id == @user.id
          status = :already_linked
        elsif @installation.user_id.present?
          record_attempt!(failure_code: "user_conflict")
          status = :conflict
        else
          record_attempt!
          @installation.user = @user
          @installation.linked_at ||= Time.current
          @installation.last_authenticated_at = Time.current
          @installation.last_link_failure_code = nil
          @installation.save!
          status = :linked
        end
      end

      case status
      when :linked
        log(:installation_link_succeeded, status: :linked)
        success(:linked)
      when :already_linked
        # Lost the race to a concurrent request for the SAME user: idempotent,
        # not a failure, and the attempt was already counted by the winner.
        success(:already_linked)
      else
        log(:installation_link_conflict, status: :conflict, failure_code: "user_conflict")
        failure(:conflict, "user_conflict")
      end
    end

    # Bookkeeping for an attempt that reached the decision step. Assigned in
    # memory; persisted by save! (link) or by the explicit save! below (conflict).
    def record_attempt!(failure_code: nil)
      now = Time.current
      @installation.first_link_attempt_at ||= now
      @installation.last_link_attempt_at = now
      @installation.link_attempts_count = @installation.link_attempts_count.to_i + 1
      @installation.runtime_context = @runtime_context if @runtime_context.present?

      return if failure_code.nil?

      @installation.last_link_failure_code = failure_code
      @installation.save!
    end

    # Idempotent no-op, with one exception: last_authenticated_at is still
    # refreshed once per TOUCH_INTERVAL, because Analytics'
    # fully_authenticated scope treats a stale timestamp as an unconfirmed link.
    # runtime_context is deliberately NOT written here — it describes the request
    # that established the link, not every request that follows it.
    def already_linked
      last = @installation.last_authenticated_at
      if last.nil? || last <= TOUCH_INTERVAL.ago
        now = Time.current
        @installation.update_columns(last_authenticated_at: now, updated_at: now)
      end

      success(:already_linked)
    end

    def invalid_input
      # No installation or no user: nothing to write, nothing to count. Must not
      # blow up on nil — callers pass whatever the request gave them.
      failure(:invalid_input, "invalid_input")
    end

    # The transaction rolled back, so the in-memory attempt bookkeeping was lost.
    # Record it separately, best-effort: a failure we cannot see is worse than a
    # slightly late counter.
    def handle_failure(status, failure_code)
      persist_failure(failure_code)
      log(:installation_link_failed, status: status, failure_code: failure_code)
      failure(status, failure_code)
    end

    def persist_failure(failure_code)
      return unless @installation.respond_to?(:persisted?) && @installation.persisted?

      # The rollback reverted the DB but NOT the in-memory counter, so increment
      # from the persisted value or the attempt would be counted twice.
      @installation.reload
      now = Time.current
      @installation.update_columns(
        first_link_attempt_at: @installation.first_link_attempt_at || now,
        last_link_attempt_at: now,
        link_attempts_count: @installation.link_attempts_count.to_i + 1,
        last_link_failure_code: failure_code,
        updated_at: now
      )
    rescue StandardError => e
      Rails.logger.warn("[installations] link_failure_bookkeeping_failed error=#{e.class}: #{e.message}")
    end

    def failure_code_for(error)
      case error
      when ActiveRecord::RecordNotUnique then "record_not_unique"
      when ActiveRecord::StaleObjectError then "stale_object"
      else "validation_failed"
      end
    end

    def success(status)
      Result.new(success: true, status: status, installation: @installation, failure_code: nil)
    end

    def failure(status, failure_code)
      Result.new(success: false, status: status, installation: @installation, failure_code: failure_code)
    end

    def report(error)
      Sentry.capture_exception(error) if defined?(Sentry) && Sentry.initialized?
    end

    # Never logs the raw installation_id: it is a stable device identifier.
    #
    # `level:` overrides the default only for a repeat of an already-reported
    # outcome: the first conflict must stay at warn (it is news), every later one
    # would be the same warn on every request the app makes.
    def log(event, status: nil, failure_code: nil, level: nil, repeat: nil)
      level ||= begin
        default = event == :installation_link_started ? :debug : :info
        if event == :installation_link_failed || event == :installation_link_conflict
          :warn
        else
          default
        end
      end

      Rails.logger.public_send(
        level,
        {
          event: event,
          producer: PRODUCER,
          installation_database_id: @installation&.id,
          installation_id_hash: installation_id_hash,
          user_id: @user&.id,
          source: @source,
          runtime_context: @runtime_context,
          status: status,
          failure_code: normalized_failure_code(failure_code),
          repeat: repeat,
          build_number: @build_number
        }.compact.to_json
      )
    end

    # Anything outside the closed vocabulary is reported as unexpected_error
    # rather than passed through, so an exception message can never become a
    # log field or a column value.
    def normalized_failure_code(code)
      return nil if code.nil?

      FAILURE_CODES.include?(code.to_s) ? code.to_s : "unexpected_error"
    end

    def installation_id_hash
      raw = @installation&.installation_id
      return nil if raw.blank?

      Digest::SHA256.hexdigest(raw)[0, 12]
    end
  end
end
