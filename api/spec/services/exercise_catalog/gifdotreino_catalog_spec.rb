require "rails_helper"
require "tmpdir"

RSpec.describe ExerciseCatalog::GifdotreinoCatalog do
  describe "#sync!" do
    it "creates and updates exercises from gifdotreino files" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        FileUtils.mkdir_p(root.join("peitoral"))
        FileUtils.touch(root.join("peitoral", "supino-reto.gif"))
        legacy = Exercise.create!(
          name: "Supino Reto",
          exercise_type: "musculacao",
          muscle_group: "chest",
          image_url: "/exercise-images/db/Bench/0.jpg"
        )

        report = described_class.new(root: root).sync!

        expect(report).to include(total_gifs: 1, updated: 1, created: 0, skipped: 0)
        expect(legacy.reload).to have_attributes(
          gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif",
          image_url: nil,
          source_dataset: "gifdotreino"
        )
      end
    end
  end

  describe "#purge_non_gifdotreino!" do
    it "reassigns compatible workout entries and deletes the non-gifdotreino exercise" do
      user = create(:user)
      plan = user.workout_plans.create!(active: true)
      day = plan.workout_days.create!(name: "Treino A", day_of_week: 1)
      legacy = Exercise.create!(
        name: "Supino",
        exercise_type: "musculacao",
        muscle_group: "chest",
        image_url: "/exercise-images/db/Bench/0.jpg"
      )
      equivalent = Exercise.create!(
        name: "Supino Reto",
        exercise_type: "musculacao",
        muscle_group: "chest",
        gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
      )
      wde = day.workout_day_exercises.create!(
        exercise: legacy,
        sets: 3,
        reps: 10,
        rest_seconds: 60,
        order_index: 0
      )

      report = described_class.new.purge_non_gifdotreino!(dry_run: false)

      expect(report[:reassigned_exercises]).to eq(1)
      expect(wde.reload.exercise).to eq(equivalent)
      expect(Exercise.exists?(legacy.id)).to be(false)
    end

    it "does not mutate records in dry-run mode" do
      legacy = Exercise.create!(
        name: "Legado",
        exercise_type: "musculacao",
        muscle_group: "chest",
        image_url: "/exercise-images/db/Legacy/0.jpg"
      )

      report = described_class.new.purge_non_gifdotreino!(dry_run: true)

      expect(report[:dry_run]).to be(true)
      expect(Exercise.exists?(legacy.id)).to be(true)
    end

    it "refuses a real purge before gifdotreino exercises exist" do
      Exercise.create!(
        name: "Legado",
        exercise_type: "musculacao",
        muscle_group: "chest",
        image_url: "/exercise-images/db/Legacy/0.jpg"
      )

      expect {
        described_class.new.purge_non_gifdotreino!(dry_run: false)
      }.to raise_error(/before importing gifdotreino/)
    end
  end
end
