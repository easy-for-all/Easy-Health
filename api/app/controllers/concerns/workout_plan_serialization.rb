# A forma do plano na API, extraída de WorkoutPlansController para que o
# endpoint anônimo devolva EXATAMENTE o mesmo shape sem duplicar 120 linhas de
# serializer que iriam divergir no primeiro campo novo.
#
# A única mudança em relação ao original é de onde vêm os dados derivados do
# dono: o que era `current_user` agora é `plan_owner` (Workouts::UserOwner ou
# Workouts::InstallationOwner). Para o dono autenticado o resultado é idêntico
# campo a campo — a suíte existente de workout_plans é o teste de regressão.
module WorkoutPlanSerialization
  extend ActiveSupport::Concern

  included do
    include ExerciseImageHelper
  end

  private

  def serialize_plan(plan)
    log = plan.ai_training_decision_log
    days = plan.workout_days.order(Arel.sql("COALESCE(position, day_of_week) ASC")).to_a
    last_completed = last_completed_at_by_day(days.map(&:id))
    payload = {
      id: plan.id,
      active: plan.active,
      created_at: plan.created_at,
      ai_rationale:           log&.rationale,
      ai_training_method:     log&.training_method,
      personalization_reason: log&.output_summary&.dig("personalization_reason"),
      user_explanation:       log&.output_summary&.dig("user_explanation"),
      coach_notes:            log&.output_summary&.dig("coach_notes"),
      days: days.map { |d| serialize_day(d, last_completed[d.id]) }
    }
    payload[:strategy] = strategy_summary(plan.workout_strategy) if FitnessIntelligence.enabled?
    payload
  end

  def strategy_summary(workout_strategy)
    return nil unless workout_strategy

    strategy = workout_strategy.strategy
    {
      version: workout_strategy.strategy_version,
      training_split: strategy["training_split"],
      primary_focus: Array(strategy["primary_focus"]),
      user_facing_explanation: strategy["user_facing_explanation"]
    }
  end

  def serialize_day(day, last_completed_at = nil)
    exercises = day.workout_day_exercises.includes(:exercise)
    {
      id: day.id,
      position: day.position,
      day_of_week: day.day_of_week,
      name: day.name,
      custom_name: day.custom_name,
      favorited: day.favorited,
      muscle_groups: exercises.map { |wde| wde.exercise.muscle_group }.compact.uniq,
      exercise_types: exercises.map { |wde| wde.exercise.exercise_type }.compact.uniq,
      exercise_count: exercises.count,
      last_completed_at: last_completed_at
    }
  end

  def serialize_day_with_exercises(day)
    wdes = day.workout_day_exercises.includes(:exercise, :workout_block).to_a
    exercise_ids   = wdes.map { |wde| wde.exercise.id }
    last_performed = exercise_last_performed(exercise_ids)
    favorite_ids   = plan_owner.favorite_exercise_ids(exercise_ids)

    {
      id: day.id,
      position: day.position,
      day_of_week: day.day_of_week,
      name: day.name,
      custom_name: day.custom_name,
      favorited: day.favorited,
      invalid_workout_reason: day.invalid_workout_reason,
      last_completed_at: last_completed_at_by_day([day.id])[day.id],
      exercises: wdes.map do |wde|
        history = plan_owner.history_for(
          exercise_id: wde.exercise.id,
          block_type: wde.workout_block&.block_type
        )

        {
          workout_day_exercise_id: wde.id,
          exercise_id: wde.exercise.id,
          name: wde.exercise.name,
          muscle_group: wde.exercise.muscle_group,
          exercise_type: wde.exercise.exercise_type,
          description: wde.exercise.description,
          instructions: wde.exercise.instructions,
          image_url: exercise_image_url(wde.exercise),
          gif_url: wde.exercise.gif_url,
          video_url: wde.exercise.video_url,
          muscle_image_url: muscle_image_url(wde.exercise.muscle_group),
          sets: wde.sets,
          reps: wde.reps,
          planned_weight_kg: wde.planned_weight,
          rest_seconds: wde.rest_seconds,
          duration_minutes: wde.duration_minutes,
          intensity: wde.intensity,
          order_index: wde.order_index,
          is_favorite: favorite_ids.include?(wde.exercise.id),
          last_performed_at: last_performed[wde.exercise.id],
          last_execution_label: history.last_execution_label,
          last_completed_at: history.last_completed_at,
          last_weight_kg: history.last_used_weight,
          suggested_weight_kg: history.suggested_starting_weight,
          progression_reason: history.progression_reason,
          **block_fields_for(wde)
        }
      end
    }
  end

  # { exercise_id => completed_at } da sessão concluída mais recente do dono.
  #
  # O filtro por dono é interpolado a partir de uma coluna e de um id inteiro
  # escolhidos aqui, nunca de input do cliente — mesma disciplina da versão
  # original, que interpolava current_user.id.
  def exercise_last_performed(exercise_ids)
    return {} if exercise_ids.empty?

    owner_column, owner_id = owner_session_filter

    rows = ActiveRecord::Base.connection.execute(<<~SQL.squish)
      SELECT DISTINCT ON ((elem->>'exercise_id')::integer)
        (elem->>'exercise_id')::integer AS exercise_id,
        completed_at
      FROM workout_sessions,
        jsonb_array_elements(exercise_logs) AS elem
      WHERE #{owner_column} = #{owner_id.to_i}
        AND status = 'completed'
        AND (elem->>'exercise_id')::integer = ANY(ARRAY[#{exercise_ids.map(&:to_i).join(',')}])
      ORDER BY (elem->>'exercise_id')::integer, completed_at DESC
    SQL

    rows.each_with_object({}) do |row, hash|
      hash[row["exercise_id"].to_i] = row["completed_at"]
    end
  end

  # { workout_day_id => completed_at } — última sessão por dia, do dono.
  def last_completed_at_by_day(day_ids)
    return {} if day_ids.empty?

    plan_owner.sessions
              .where(workout_day_id: day_ids, status: "completed")
              .select("DISTINCT ON (workout_day_id) workout_day_id, completed_at")
              .order("workout_day_id, completed_at DESC")
              .each_with_object({}) { |s, h| h[s.workout_day_id] = s.completed_at }
  end

  def owner_session_filter
    if plan_owner.anonymous?
      [ "app_installation_id", plan_owner.installation.id ]
    else
      [ "user_id", plan_owner.user.id ]
    end
  end
end
