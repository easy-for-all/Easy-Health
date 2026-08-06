class AddInstallationOwnerToWorkoutSessions < ActiveRecord::Migration[8.1]
  # O segundo (e último) nó-raiz com dono. Uma sessão anônima precisa existir de
  # verdade, e não só no dispositivo: o primeiro treino executado é a métrica
  # central do experimento e tem que sobreviver ao cadastro.
  def up
    change_column_null :workout_sessions, :user_id, true
    add_reference :workout_sessions, :app_installation, foreign_key: true, index: true

    add_check_constraint :workout_sessions,
                         "(user_id IS NULL) <> (app_installation_id IS NULL)",
                         name: "workout_sessions_single_owner"
  end

  def down
    remove_check_constraint :workout_sessions, name: "workout_sessions_single_owner"
    remove_reference :workout_sessions, :app_installation, foreign_key: true
    change_column_null :workout_sessions, :user_id, false
  end
end
