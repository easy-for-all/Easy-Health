module Api
  module V1
    class WorkoutDayExercisesController < BaseController
      include WorkoutBlockSerialization

      before_action :require_active_access!, only: [:swap]
      before_action(only: [:swap, :update, :reorder]) { check_rate_limit!(:update_workout) }

      def swap
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        replacement = Exercise.browseable.find(params[:replacement_exercise_id])
        current_exercise_ids = wde.workout_day.workout_day_exercises.where.not(id: wde.id).pluck(:exercise_id)

        if current_exercise_ids.include?(replacement.id)
          return render json: { error: "Exercício já está neste treino.", error_code: "already_in_workout" }, status: :unprocessable_entity
        end

        force = params[:force].to_s == "true"
        unless force || same_target?(wde.exercise, replacement)
          return render json: {
            error: "O exercício selecionado é de grupo muscular diferente. Confirmar mesmo assim?",
            error_code: "muscle_group_mismatch",
            can_force: true
          }, status: :unprocessable_entity
        end

        wde.update!(exercise: replacement)

        render json: workout_day_exercise_json(wde.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def update
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        wde.update!(update_params)
        render json: workout_day_exercise_json(wde.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def destroy
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        if wde.workout_day.workout_day_exercises.count <= 1
          return render json: { error: "Cannot remove the last exercise from a workout day" }, status: :unprocessable_entity
        end

        wde.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def reorder
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:workout_day_id])

        ordered_ids = Array(params[:ordered_ids]).map(&:to_i)
        existing_ids = day.workout_day_exercises.pluck(:id)

        unless (ordered_ids - existing_ids).empty? && (existing_ids - ordered_ids).empty?
          return render json: { error: "Invalid exercise IDs" }, status: :unprocessable_entity
        end

        wdes_by_id = day.workout_day_exercises.index_by(&:id)
        # This endpoint only reassigns order_index (moving whole blocks
        # relative to each other); it never lets the client move a wde into a
        # different block. position_in_block is recomputed here from each
        # wde's relative order within the block it already belongs to.
        position_in_block_counters = Hash.new(0)

        WorkoutDayExercise.transaction do
          ordered_ids.each_with_index do |id, idx|
            wde = wdes_by_id.fetch(id)
            block_id = wde.workout_block_id
            wde.update!(order_index: idx, position_in_block: position_in_block_counters[block_id])
            position_in_block_counters[block_id] += 1
          end
        end

        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def create
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id, active: true })
          .find(params[:workout_day_id])

        exercise = Exercise.browseable.find(params[:exercise_id])
        current_exercise_ids = day.workout_day_exercises.pluck(:exercise_id)

        if current_exercise_ids.include?(exercise.id)
          return render json: { error: "Exercise is already in this workout" }, status: :unprocessable_entity
        end

        next_order = (day.workout_day_exercises.maximum(:order_index) || -1) + 1

        if WorkoutDayExercise::CARDIO_TYPES.include?(exercise.exercise_type)
          wde = day.workout_day_exercises.create!(
            exercise: exercise,
            sets: 1,
            reps: 1,
            rest_seconds: 0,
            duration_minutes: cardio_create_params[:duration_minutes]&.to_i || 20,
            intensity: cardio_create_params[:intensity] || "moderado",
            order_index: next_order
          )
        else
          reference = day.workout_day_exercises.includes(:exercise).find { |wde| same_target?(wde.exercise, exercise) }
          unless reference
            return render json: { error: "Exercise must match a muscle group already trained here" }, status: :unprocessable_entity
          end

          wde = day.workout_day_exercises.create!(
            exercise: exercise,
            sets: reference.sets,
            reps: reference.reps,
            rest_seconds: reference.rest_seconds,
            order_index: next_order
          )
        end

        render json: workout_day_exercise_json(wde), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      # Creates a composite block (superset/bi_set/tri_set/circuit) with all
      # its exercises in one shot. Unlike #create, this never calls
      # same_target? - a brand new block's exercises don't need to match the
      # muscle group of anything already in the day (e.g. an antagonist
      # superset legitimately pairs chest + back).
      def create_block
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id, active: true })
          .find(params[:workout_day_id])

        block_type = params[:block_type].to_s
        unless WorkoutBlock::MULTI_EXERCISE_TYPES.include?(block_type)
          return render json: { error: "block_type must be one of #{WorkoutBlock::MULTI_EXERCISE_TYPES.join(', ')}" }, status: :unprocessable_entity
        end

        exercise_params = Array(params[:exercises])
        unless block_exercise_count_valid?(block_type, exercise_params.size)
          return render json: { error: "Invalid number of exercises for block_type #{block_type}" }, status: :unprocessable_entity
        end

        exercise_ids = exercise_params.map { |e| e[:exercise_id].to_i }
        if exercise_ids.uniq.size != exercise_ids.size
          return render json: { error: "Duplicate exercise in block" }, status: :unprocessable_entity
        end

        current_exercise_ids = day.workout_day_exercises.pluck(:exercise_id)
        if (exercise_ids & current_exercise_ids).any?
          return render json: { error: "Exercise is already in this workout" }, status: :unprocessable_entity
        end

        exercises = exercise_ids.map { |id| Exercise.browseable.find(id) }
        if exercises.any? { |ex| WorkoutDayExercise::CARDIO_TYPES.include?(ex.exercise_type) }
          return render json: { error: "Cardio exercises are not supported in composite blocks yet" }, status: :unprocessable_entity
        end

        rounds = params[:rounds].presence&.to_i || 1
        rest_between_rounds_seconds = params[:rest_between_rounds_seconds].presence&.to_i

        block = nil
        wdes = []

        WorkoutDayExercise.transaction do
          next_block_position = (day.workout_blocks.maximum(:position) || -1) + 1
          block = day.workout_blocks.create!(
            block_type: block_type,
            position: next_block_position,
            rounds: rounds,
            rest_between_rounds_seconds: rest_between_rounds_seconds
          )

          next_order = (day.workout_day_exercises.maximum(:order_index) || -1) + 1

          exercise_params.each_with_index do |ex_params, idx|
            # workout_block/position_in_block are set explicitly here so
            # ensure_single_block! (before_create) never fires - if it did,
            # each exercise would silently get wrapped in its own separate
            # "single" block instead of joining this composite one.
            wdes << day.workout_day_exercises.create!(
              exercise: exercises[idx],
              sets: ex_params[:sets],
              reps: ex_params[:reps],
              rest_seconds: ex_params[:rest_seconds] || 0,
              planned_weight: ex_params[:planned_weight],
              order_index: next_order + idx,
              workout_block: block,
              position_in_block: idx
            )
          end
        end

        render json: {
          block_id: block.id,
          block_type: block.block_type,
          exercises: wdes.map { |wde| workout_day_exercise_json(wde) }
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def block_exercise_count_valid?(block_type, count)
        case block_type
        when "superset", "bi_set" then count == 2
        when "tri_set" then count == 3
        when "circuit" then count >= 3
        else false
        end
      end

      def update_params
        params.permit(:sets, :reps, :rest_seconds, :duration_minutes, :intensity, :weight_kg)
      end

      def cardio_create_params
        params.permit(:duration_minutes, :intensity)
      end

      def same_target?(current, replacement)
        current.muscle_group.present? ? current.muscle_group == replacement.muscle_group : current.exercise_type == replacement.exercise_type
      end

      def workout_day_exercise_json(wde)
        exercise = wde.exercise
        {
          workout_day_exercise_id: wde.id,
          exercise_id: exercise.id,
          name: exercise.name,
          muscle_group: exercise.muscle_group,
          exercise_type: exercise.exercise_type,
          description: exercise.description,
          image_url: exercise_image_url(exercise),
          muscle_image_url: muscle_image_url(exercise.muscle_group),
          sets: wde.sets,
          reps: wde.reps,
          rest_seconds: wde.rest_seconds,
          duration_minutes: wde.duration_minutes,
          intensity: wde.intensity,
          order_index: wde.order_index,
          **block_fields_for(wde)
        }
      end

      include ExerciseImageHelper
    end
  end
end
