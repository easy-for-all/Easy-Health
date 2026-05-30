class AddNewMuscleGroupsToExercises < ActiveRecord::Migration[8.1]
  def up
    say "Expanding MUSCLE_GROUPS to include: forearms, calves, glutes, trapezius"
    say "No column changes needed — muscle_group is already a string column."
    say "Validation expanded in the Exercise model."
  end

  def down
    say "Reversing: exercises with new muscle groups will fail model validation until manually re-assigned."
  end
end
