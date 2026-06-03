class CreateClientPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :client_permissions do |t|
      t.references :personal_client_relationship, null: false, foreign_key: true, index: { unique: true }
      t.boolean :can_view_assigned_workouts,    default: true,  null: false
      t.boolean :can_view_completed_workouts,   default: true,  null: false
      t.boolean :can_view_adherence,            default: true,  null: false
      t.boolean :can_view_exercise_performance, default: false, null: false
      t.boolean :can_view_body_weight,          default: false, null: false
      t.boolean :can_view_photos,               default: false, null: false
      t.boolean :can_view_body_analysis,        default: false, null: false
      t.boolean :can_view_exams,                default: false, null: false

      t.timestamps
    end
  end
end
