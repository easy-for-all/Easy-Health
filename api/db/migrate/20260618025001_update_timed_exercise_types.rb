class UpdateTimedExerciseTypes < ActiveRecord::Migration[8.1]
  TIMED_PATTERNS = %w[
    prancha
    plank
    hollow
    wall\ sit
    isometric
    vacuo
    bird\ dog
    dead\ bug
    side\ plank
    prancha\ lateral
    superman
    glute\ bridge\ hold
  ].freeze

  def up
    TIMED_PATTERNS.each do |pattern|
      execute <<~SQL
        UPDATE exercises
        SET exercise_type = 'timed'
        WHERE LOWER(name) LIKE '%#{pattern}%'
          AND exercise_type != 'timed'
      SQL
    end
  end

  def down
    execute <<~SQL
      UPDATE exercises
      SET exercise_type = 'musculacao'
      WHERE exercise_type = 'timed'
    SQL
  end
end
