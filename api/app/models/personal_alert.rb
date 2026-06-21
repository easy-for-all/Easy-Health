class PersonalAlert < ApplicationRecord
  KINDS = %w[pause trophy warning trend info].freeze

  belongs_to :personal, class_name: "User"
  belongs_to :client,   class_name: "User", optional: true

  scope :unread,    -> { where(read_at: nil) }
  scope :for_personal, ->(user) { where(personal: user).order(created_at: :desc) }

  def unread? = read_at.nil?
  def mark_read! = update!(read_at: Time.current) if unread?
end
