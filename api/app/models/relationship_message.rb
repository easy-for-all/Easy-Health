class RelationshipMessage < ApplicationRecord
  belongs_to :user
  belongs_to :user_event, optional: true

  CHANNELS  = %w[email push whatsapp sms in_app].freeze
  PROVIDERS = %w[brevo sendgrid make internal].freeze
  STATUSES  = %w[pending sent failed skipped delivered opened clicked].freeze

  validates :event_name, presence: true
  validates :channel,    inclusion: { in: CHANNELS }
  validates :provider,   inclusion: { in: PROVIDERS }
  validates :status,     inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true, allow_nil: true
end
