namespace :workout_intelligence do
  desc "Enrich curated exercises with technical level / role metadata for the workout generator"
  task enrich_exercise_metadata: :environment do
    all_exercises = Exercise.all.to_a
    matched = 0
    unmatched = []

    WorkoutIntelligence::ExerciseEnrichmentSeed::RECORDS.each do |record|
      exercise = WorkoutIntelligence::NameMatcher.best_match(record[:name], all_exercises)

      unless exercise
        unmatched << record[:name]
        next
      end

      exercise.update!(
        technical_complexity: record[:technical_complexity],
        risk_level: record[:risk_level],
        calisthenics_skill: record[:calisthenics_skill],
        movement_pattern: record[:movement_pattern],
        compound: record.fetch(:compound, nil),
        unilateral: record.fetch(:unilateral, false),
        requires_barbell_skill: record.fetch(:requires_barbell_skill, false),
        requires_bodyweight_strength: record.fetch(:requires_bodyweight_strength, false),
        objective_tags: record.fetch(:objective_tags, []),
        style_tags: record.fetch(:style_tags, [])
      )
      matched += 1
    end

    # Second pass: resolve regressions now that the curated exercises exist.
    browseable = Exercise.browseable.to_a
    WorkoutIntelligence::ExerciseEnrichmentSeed::RECORDS.each do |record|
      exercise = WorkoutIntelligence::NameMatcher.best_match(record[:name], all_exercises)
      next unless exercise

      regression = WorkoutIntelligence::RegressionMap.resolve(exercise.name, scope: browseable)
      next unless regression && regression.id != exercise.id

      exercise.update_column(:regression_exercise_id, regression.id)
    end

    puts "Enrichment done. Matched: #{matched}/#{WorkoutIntelligence::ExerciseEnrichmentSeed::RECORDS.size}"
    if unmatched.any?
      puts "Unmatched (review manually):"
      unmatched.each { |name| puts "  - #{name}" }
    end
  end

  desc "List the most-used exercises in persisted workout plans, to prioritize enrichment"
  task usage_report: :environment do
    counts = WorkoutDayExercise
      .joins(:exercise)
      .where(exercises: { exercise_type: "musculacao" })
      .group("exercises.name")
      .order(Arel.sql("count(*) desc"))
      .limit(80)
      .count

    counts.each { |name, count| puts "#{count}\t#{name}" }
  end

  desc "Report how much of the exercise catalog still lacks intelligence metadata"
  task coverage_report: :environment do
    total = Exercise.browseable.count
    classified = Exercise.browseable.where.not(technical_complexity: nil).or(Exercise.browseable.where.not(calisthenics_skill: nil)).count

    puts "Browseable exercises: #{total}"
    puts "Classified (technical_complexity or calisthenics_skill set): #{classified} (#{(classified.to_f / total * 100).round(1)}%)"
    puts "Falling back to name-pattern classification: #{total - classified}"

    puts "\nBy muscle_group, unclassified count:"
    Exercise.browseable.where(technical_complexity: nil, calisthenics_skill: nil)
      .group(:muscle_group).order(Arel.sql("count(*) desc")).count.each do |group, count|
      puts "  #{group || 'nil'}: #{count}"
    end
  end
end
