# Deterministic, persistent A/B assignment for the activation-push experiment.
# The variant is computed once from a stable hash of the user id and stored on
# the notification preferences row so it never changes between runs.
#
# When the experiment flag is OFF, everyone is "treatment" and we do NOT persist
# (so enabling the experiment later still produces a clean 50/50 split).
class ExperimentAssignment
  EXPERIMENT = "activation_push_v1".freeze

  def self.variant_for(user)
    prefs = user.notification_preferences!
    return prefs.activation_push_variant if prefs.activation_push_variant.present?
    return "treatment" unless PushActivationEligibility.experiment_enabled?

    variant = deterministic_variant(user)
    prefs.update!(activation_push_variant: variant)
    variant
  end

  def self.deterministic_variant(user)
    digest = Digest::SHA256.hexdigest("#{EXPERIMENT}:#{user.id}")
    digest[0, 8].to_i(16).even? ? "treatment" : "control"
  end
end
