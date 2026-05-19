class EquipmentIdentification < ApplicationRecord
  belongs_to :user
  belongs_to :exercise, optional: true
end
