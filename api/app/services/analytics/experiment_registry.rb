module Analytics
  # The closed vocabulary of product experiments.
  #
  # Why a registry and not free-form strings: the assignment table has UNIQUE
  # partial indexes on (experiment_key, subject), and the write path is an
  # unauthenticated endpoint. Without an allowlist, any client could mint rows
  # under arbitrary keys and variants — the index would faithfully deduplicate
  # garbage, and the admin panel would divide by it.
  #
  # A key here is a claim that the panel knows how to read. Adding one means
  # deciding what its variants are BEFORE any data exists, which is also what
  # keeps a running experiment from silently gaining a third arm.
  class ExperimentRegistry
    ANDROID_POST_ONBOARDING_GATE = "android_post_onboarding_gate_v1".freeze

    EXPERIMENTS = {
      ANDROID_POST_ONBOARDING_GATE => %w[account_gate open_app].freeze
    }.freeze

    class << self
      def known?(experiment_key)
        EXPERIMENTS.key?(experiment_key.to_s)
      end

      def variants(experiment_key)
        EXPERIMENTS.fetch(experiment_key.to_s, [].freeze)
      end

      def valid_variant?(experiment_key, variant)
        variants(experiment_key).include?(variant.to_s)
      end
    end
  end
end
