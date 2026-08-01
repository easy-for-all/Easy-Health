module Analytics
  # The one place that decides whether an account is real acquisition or not.
  #
  # This exists because the first "linked" installation of every Android release
  # turned out to be us or a robot: hello@easyhealth.art, the developer's own
  # Gmail, and above all the Google Play pre-launch report, which drives a real
  # device through the whole sign-up flow with a @cloudtestlabaccounts.com
  # address. Counted together with real users, two automated runs looked exactly
  # like "the release converted 2/2" — and that is the number that hid the fact
  # that no external user was converting at all.
  #
  # Deliberately NOT a device heuristic. `manufacturer == "Google"` was rejected
  # as a criterion: a Pixel is a Google device and its owner is a real user.
  # Identity is the only thing that separates a test run from an acquisition.
  #
  # Read-only and non-destructive by construction: nothing here writes to a User,
  # deletes a row or rewrites history. Classification is applied at query time so
  # the raw data stays intact and "Todos" remains available for diagnosis.
  module AccountClassification
    EXTERNAL       = :external
    INTERNAL       = :internal
    AUTOMATED_TEST = :automated_test

    CLASSIFICATIONS = [ EXTERNAL, INTERNAL, AUTOMATED_TEST ].freeze

    # Google Play pre-launch report / Firebase Test Lab. Hardcoded because it is
    # a Google-owned constant, not a configuration of ours — an unset env must
    # never silently let robot runs back into the acquisition numbers.
    DEFAULT_AUTOMATED_TEST_DOMAINS = %w[cloudtestlabaccounts.com].freeze

    # Known internal accounts. Defaults live in code for the same reason: this is
    # the list that was already polluting production KPIs, and it must hold even
    # if the env is missing on a server.
    DEFAULT_INTERNAL_EMAILS = %w[
      hello@easyhealth.art
      mail.marcus.reis@gmail.com
      test.user@example.com
      t13@gmail.com
    ].freeze

    DEFAULT_INTERNAL_DOMAINS = %w[easyhealth.art].freeze

    module_function

    def automated_test_domains
      env_list("ANALYTICS_AUTOMATED_TEST_EMAIL_DOMAINS") | DEFAULT_AUTOMATED_TEST_DOMAINS
    end

    def internal_domains
      env_list("ANALYTICS_INTERNAL_EMAIL_DOMAINS") | DEFAULT_INTERNAL_DOMAINS
    end

    def internal_emails
      env_list("ANALYTICS_INTERNAL_EMAILS") | DEFAULT_INTERNAL_EMAILS
    end

    # @param user [User, nil]
    # @return [Symbol] :external | :internal | :automated_test
    def for(user)
      return EXTERNAL if user.nil?

      email = user.email.to_s.downcase.strip
      return AUTOMATED_TEST if domain_match?(email, automated_test_domains)
      return INTERNAL if user.try(:test_account)
      return INTERNAL if internal_emails.include?(email)
      return INTERNAL if domain_match?(email, internal_domains)

      EXTERNAL
    end

    def external?(user)
      self.for(user) == EXTERNAL
    end

    # SQL-side counterpart of `.for`, so a scope and a per-record check can never
    # disagree. Excludes internal AND automated-test accounts in one pass.
    #
    # @param relation [ActiveRecord::Relation] a User relation
    def exclude_non_external(relation)
      rel = relation
      rel = rel.where(test_account: false) if User.column_names.include?("test_account")

      emails = internal_emails
      rel = rel.where.not(User.arel_table[:email].lower.in(emails)) if emails.any?

      (automated_test_domains | internal_domains).each do |domain|
        rel = rel.where.not("users.email ILIKE ?", "%@#{domain}")
      end

      rel
    end

    # Only the robot runs, kept separate from internal so the admin can tell
    # "Google Test Lab" apart from "us testing on our own phones".
    def automated_test_scope(relation)
      domains = automated_test_domains
      return relation.none if domains.empty?

      condition = domains.map { "users.email ILIKE ?" }.join(" OR ")
      relation.where(condition, *domains.map { |d| "%@#{d}" })
    end

    def internal_scope(relation)
      # Internal = flagged, listed, or on an internal domain — minus the robots,
      # which are reported in their own bucket.
      emails = internal_emails
      clauses = internal_domains.map { "users.email ILIKE ?" }
      binds   = internal_domains.map { |d| "%@#{d}" }

      if emails.any?
        clauses << "LOWER(users.email) IN (#{emails.map { '?' }.join(', ')})"
        binds.concat(emails)
      end

      if User.column_names.include?("test_account")
        clauses << "users.test_account = TRUE"
      end

      return relation.none if clauses.empty?

      scope = relation.where(clauses.join(" OR "), *binds)
      automated_test_domains.each { |d| scope = scope.where.not("users.email ILIKE ?", "%@#{d}") }
      scope
    end

    def env_list(key)
      ENV.fetch(key, "").split(",").map { |v| v.strip.downcase }.reject(&:blank?)
    end

    def domain_match?(email, domains)
      return false if email.blank?

      domain = email.split("@").last.to_s
      domains.any? { |d| domain == d }
    end
  end
end
