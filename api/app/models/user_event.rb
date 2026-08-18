class UserEvent < ApplicationRecord
  DELIVERY_STATUSES = %w[
    pending
    sending
    accepted_by_make
    retrying
    failed_to_reach_make
    dead_letter
    disabled
    skipped
  ].freeze
  PROCESSING_STATUSES = %w[unknown received routed filtered completed failed sent skipped].freeze
  ERROR_DELIVERY_STATUSES = %w[failed_to_reach_make dead_letter].freeze
  ACTIVE_DELIVERY_STATUSES = %w[pending sending retrying].freeze

  belongs_to :user
  # Pushes Make asked for because of this event. nullify on delete keeps the
  # dispatch audit trail even if the event is ever removed.
  has_many :push_dispatches, dependent: :nullify
  has_many :relationship_messages, dependent: :nullify

  validates :event_name, presence: true
  validates :make_delivery_status, inclusion: { in: DELIVERY_STATUSES }
  validates :make_processing_status, inclusion: { in: PROCESSING_STATUSES }

  # "We attempted to hand this event to Make." Deliberately tolerant: the make_*
  # columns were filled in by different code over time, so older rows can carry
  # a delivered status with no first_attempt_at, or attempts with no timestamps.
  # Testing a single column would under-count history. New rows write all of
  # them consistently; nothing is backfilled.
  SENT_TO_MAKE_SQL = <<~SQL.squish.freeze
    (user_events.make_attempts_count > 0
     OR user_events.make_first_attempt_at IS NOT NULL
     OR user_events.make_last_attempt_at IS NOT NULL
     OR user_events.make_delivered_to_provider_at IS NOT NULL
     OR user_events.make_delivery_status = 'accepted_by_make')
  SQL

  scope :sent_to_make, -> { where(Arel.sql(SENT_TO_MAKE_SQL)) }
  # COALESCE because a plain NOT over a NULL column evaluates to NULL and would
  # silently drop exactly the rows a coverage report exists to find.
  scope :not_sent_to_make, -> { where(Arel.sql("NOT COALESCE(#{SENT_TO_MAKE_SQL}, FALSE)")) }
  scope :pending_make_delivery, -> { where(make_delivery_status: "pending") }
  scope :accepted_by_make, -> { where(make_delivery_status: "accepted_by_make") }
  scope :failed_make_delivery, -> { where(make_delivery_status: ERROR_DELIVERY_STATUSES) }
  scope :skipped_make_delivery, -> { where(make_delivery_status: "skipped") }
  scope :active_make_delivery, -> { where(make_delivery_status: ACTIVE_DELIVERY_STATUSES) }

  def make_delivery_channels_list
    Array(make_delivery_channels).map(&:to_s).reject(&:blank?)
  end
end
