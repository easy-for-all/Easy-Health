class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :health_profile, dependent: :destroy
  has_many :workout_plans, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :user_media, class_name: "UserMedia", dependent: :destroy
  has_one_attached :avatar

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def active_workout_plan
    workout_plans.active.first
  end
end
