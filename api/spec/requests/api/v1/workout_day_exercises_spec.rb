require "rails_helper"

RSpec.describe "Api::V1::WorkoutDayExercises", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:headers) { { "Content-Type" => "application/json" } }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }
  let(:current_exercise) do
    Exercise.create!(
      name: "Supino Reto",
      exercise_type: "musculacao",
      muscle_group: "chest",
      gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
    )
  end
  let(:invalid_exercise) do
    Exercise.create!(
      name: "Supino JPG",
      exercise_type: "musculacao",
      muscle_group: "chest",
      image_url: "/exercise-images/db/Barbell_Bench_Press/0.jpg"
    )
  end
  let!(:wde) do
    day.workout_day_exercises.create!(
      exercise: current_exercise,
      sets: 3,
      reps: 10,
      rest_seconds: 60,
      order_index: 0
    )
  end

  before { sign_in user }

  it "rejects swapping to an exercise outside the gifdotreino catalog" do
    post "/api/v1/workout_day_exercises/#{wde.id}/swap",
      params: { replacement_exercise_id: invalid_exercise.id }.to_json,
      headers: headers

    expect(response).to have_http_status(:not_found)
    expect(wde.reload.exercise_id).to eq(current_exercise.id)
  end

  it "rejects adding an exercise outside the gifdotreino catalog" do
    post "/api/v1/workout_days/#{day.id}/exercises",
      params: { exercise_id: invalid_exercise.id }.to_json,
      headers: headers

    expect(response).to have_http_status(:not_found)
    expect(day.workout_day_exercises.reload.pluck(:exercise_id)).to contain_exactly(current_exercise.id)
  end

  describe "swapping an exercise inside a superset" do
    let(:exercise_a2) do
      Exercise.create!(
        name: "Remada Baixa", exercise_type: "musculacao", muscle_group: "chest",
        gif_url: "/exercise-images/gifdotreino/costas/remada-baixa.gif"
      )
    end
    let(:replacement) do
      Exercise.create!(
        name: "Supino Inclinado", exercise_type: "musculacao", muscle_group: "chest",
        gif_url: "/exercise-images/gifdotreino/peitoral/supino-inclinado.gif"
      )
    end
    let!(:block) { day.workout_blocks.create!(block_type: "superset", position: 1, rounds: 3) }
    let!(:wde_a2) do
      day.workout_day_exercises.create!(
        exercise: exercise_a2, sets: 3, reps: 10, rest_seconds: 0, order_index: 1,
        workout_block: block, position_in_block: 1
      )
    end

    before { wde.update!(workout_block: block, position_in_block: 0) }

    it "replaces only A1, keeping A2 and the block structure intact" do
      post "/api/v1/workout_day_exercises/#{wde.id}/swap",
        params: { replacement_exercise_id: replacement.id }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["exercise_id"]).to eq(replacement.id)
      expect(body["block_type"]).to eq("superset")
      expect(body["block_id"]).to eq(block.id)
      expect(body["position_in_block"]).to eq(0)

      wde.reload
      wde_a2.reload
      expect(wde.exercise_id).to eq(replacement.id)
      expect(wde.workout_block_id).to eq(block.id)
      expect(wde.position_in_block).to eq(0)
      expect(wde_a2.exercise_id).to eq(exercise_a2.id)
      expect(wde_a2.workout_block_id).to eq(block.id)
      expect(wde_a2.position_in_block).to eq(1)
    end
  end

  describe "POST /api/v1/workout_days/:workout_day_id/blocks" do
    let(:back_exercise) do
      Exercise.create!(
        name: "Remada Baixa", exercise_type: "musculacao", muscle_group: "back",
        gif_url: "/exercise-images/gifdotreino/costas/remada-baixa.gif"
      )
    end
    let(:shoulders_exercise) do
      Exercise.create!(
        name: "Desenvolvimento", exercise_type: "musculacao", muscle_group: "shoulders",
        gif_url: "/exercise-images/gifdotreino/ombros/desenvolvimento.gif"
      )
    end
    let(:core_exercise) do
      Exercise.create!(
        name: "Prancha", exercise_type: "musculacao", muscle_group: "core",
        gif_url: "/exercise-images/gifdotreino/core/prancha.gif"
      )
    end
    let(:cardio_exercise) do
      Exercise.create!(
        name: "Esteira", exercise_type: "corrida",
        gif_url: "/exercise-images/gifdotreino/cardio/esteira.gif"
      )
    end

    def post_block(body)
      post "/api/v1/workout_days/#{day.id}/blocks", params: body.to_json, headers: headers
    end

    it "creates a superset with 2 exercises sharing the same block, in position order" do
      post_block(
        block_type: "superset",
        rounds: 3,
        rest_between_rounds_seconds: 90,
        exercises: [
          { exercise_id: back_exercise.id, sets: 3, reps: 10, rest_seconds: 0 },
          { exercise_id: shoulders_exercise.id, sets: 3, reps: 10, rest_seconds: 0 }
        ]
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["block_type"]).to eq("superset")
      returned = body["exercises"]
      expect(returned.size).to eq(2)
      expect(returned.map { |e| e["block_id"] }.uniq).to eq([body["block_id"]])
      expect(returned.map { |e| e["position_in_block"] }).to eq([0, 1])

      block = WorkoutBlock.find(body["block_id"])
      expect(block.rounds).to eq(3)
      expect(block.rest_between_rounds_seconds).to eq(90)
    end

    it "creates a circuit with 3+ exercises, persisting rounds and rest_between_rounds_seconds" do
      post_block(
        block_type: "circuit",
        rounds: 4,
        rest_between_rounds_seconds: 60,
        exercises: [
          { exercise_id: back_exercise.id, sets: 1, reps: 12, rest_seconds: 0 },
          { exercise_id: shoulders_exercise.id, sets: 1, reps: 12, rest_seconds: 0 },
          { exercise_id: core_exercise.id, sets: 1, reps: 12, rest_seconds: 0 }
        ]
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["exercises"].size).to eq(3)
      block = WorkoutBlock.find(body["block_id"])
      expect(block.block_type).to eq("circuit")
      expect(block.rounds).to eq(4)
      expect(block.rest_between_rounds_seconds).to eq(60)
    end

    it "rejects a duplicate exercise within the same payload" do
      post_block(
        block_type: "superset",
        exercises: [
          { exercise_id: back_exercise.id, sets: 3, reps: 10 },
          { exercise_id: back_exercise.id, sets: 3, reps: 10 }
        ]
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WorkoutBlock.where(workout_day: day, block_type: "superset").count).to eq(0)
    end

    it "rejects an exercise already present in the day" do
      post_block(
        block_type: "superset",
        exercises: [
          { exercise_id: current_exercise.id, sets: 3, reps: 10 },
          { exercise_id: back_exercise.id, sets: 3, reps: 10 }
        ]
      )

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an exercise outside the gifdotreino catalog with 404" do
      post_block(
        block_type: "superset",
        exercises: [
          { exercise_id: invalid_exercise.id, sets: 3, reps: 10 },
          { exercise_id: back_exercise.id, sets: 3, reps: 10 }
        ]
      )

      expect(response).to have_http_status(:not_found)
      expect(WorkoutBlock.where(workout_day: day, block_type: "superset").count).to eq(0)
    end

    it "rejects the wrong exercise count for the block type" do
      post_block(block_type: "superset", exercises: [ { exercise_id: back_exercise.id, sets: 3, reps: 10 } ])
      expect(response).to have_http_status(:unprocessable_entity)

      # Request-spec sessions here don't carry across multiple requests in
      # the same example (see authed_post comment in workout_sessions_spec.rb).
      sign_in user
      post_block(
        block_type: "circuit",
        exercises: [
          { exercise_id: back_exercise.id, sets: 3, reps: 10 },
          { exercise_id: shoulders_exercise.id, sets: 3, reps: 10 }
        ]
      )
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects cardio exercises" do
      post_block(
        block_type: "superset",
        exercises: [
          { exercise_id: cardio_exercise.id, sets: 3, reps: 10 },
          { exercise_id: back_exercise.id, sets: 3, reps: 10 }
        ]
      )

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rolls back the whole block when one exercise fails to persist (no partial block)" do
      post_block(
        block_type: "superset",
        exercises: [
          { exercise_id: back_exercise.id, sets: 3, reps: 10 },
          { exercise_id: shoulders_exercise.id, sets: nil, reps: nil } # missing required fields -> RecordInvalid
        ]
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WorkoutBlock.where(workout_day: day, block_type: "superset").count).to eq(0)
      expect(day.workout_day_exercises.reload.pluck(:exercise_id)).to contain_exactly(current_exercise.id)
    end
  end
end
