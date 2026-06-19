require "net/http"
require "json"
require "fileutils"

SLUG_MAP = {
  # Musculação — peito
  "Flexão de Braço"          => "Pushups",
  "Supino"                   => "Barbell_Bench_Press_-_Medium_Grip",
  # Musculação — costas
  "Barra Fixa"               => "Pullups",
  "Remada Curvada"           => "Bent_Over_Barbell_Row",
  # Musculação — ombros
  "Desenvolvimento"          => "Barbell_Shoulder_Press",
  "Elevação Lateral"         => "Lateral_Raise_-_With_Bands",
  # Musculação — bíceps
  "Rosca Direta"             => "Barbell_Curl",
  "Rosca Martelo"            => "Alternate_Hammer_Curl",
  # Musculação — tríceps
  "Mergulho no Banco"        => "Bench_Dips",
  "Tríceps Francês"          => "Band_Skull_Crusher",
  "Tríceps no Banco"         => "Bench_Dips",
  # Musculação — pernas
  "Agachamento"              => "Barbell_Squat",
  "Avanço"                   => "Barbell_Lunge",
  "Levantamento Terra"       => "Barbell_Deadlift",
  "Panturrilha em Pé"        => "Calf_Raise_On_A_Dumbbell",
  "Elevação Pélvica"         => "Barbell_Hip_Thrust",
  "Ponte Unilateral"         => "Butt_Lift_Bridge",
  "Afundo Reverso"           => "Crossover_Reverse_Lunge",
  # Musculação — core
  "Prancha"                  => "Plank",
  "Abdominal"                => "3_4_Sit-Up",
  "Abdominal Bicicleta"      => "Air_Bike",
  # Cardio
  "Pular Corda"              => "Battling_Ropes",
  "Remo Ergômetro"           => "Bent_Over_Barbell_Row",
  "Bicicleta"                => "Air_Bike",
  "Elíptico"                 => "Elliptical_Trainer",
  "Corrida Esteira"          => "Jogging_Treadmill",
  "Corrida Rua"              => "Jogging_Treadmill",
  "Corrida Estacionária"     => "Mountain_Climbers",
  # HIIT
  "Burpee"                   => "Freehand_Jump_Squat",
  "Salto na Caixa"           => "Front_Box_Jump",
  "Escalador"                => "Mountain_Climbers",
  "Agachamento com Salto"    => "Freehand_Jump_Squat",
  "Polichinelo"              => "Arm_Circles",
  "Mountain Climber"         => "Mountain_Climbers",
  "Agachamento Isométrico"   => "Barbell_Squat",
  # Funcional
  "Swing com Kettlebell"     => "One-Arm_Kettlebell_Swings",
  "Remada no TRX"            => "Alternating_Renegade_Row",
  "Corda Naval"              => "Battling_Ropes",
  "Arremesso de Medicine Ball" => "Backward_Medicine_Ball_Throw",
  # Natação (best visual approximation)
  "Nado Livre"               => "Barbell_Deadlift",
  "Borboleta"                => "Barbell_Deadlift",
  # Caminhada
  "Caminhada Moderada"       => "Farmers_Walk",
  "Caminhada em Inclinação"  => "Bodyweight_Walking_Lunge",
}.freeze

namespace :exercises do
  desc "Copy images from local free-exercise-db to public/exercise-images/db and update DB"
  task import_local_images: :environment do
    dest_root = Rails.root.join("public", "exercise-images", "db")

    # Try to find the local image source (dev host or prod with mounted volume)
    local_db = [
      Rails.root.join("..", "external", "free-exercise-db", "exercises"),
      Pathname.new("/external/free-exercise-db/exercises"),
    ].find { |p| p.directory? }

    copied  = 0
    db_updated = 0

    SLUG_MAP.each do |name, slug|
      if local_db
        src_path = local_db.join(slug, "0.jpg")
        if File.exist?(src_path)
          dest_dir = dest_root.join(slug)
          FileUtils.mkdir_p(dest_dir)
          FileUtils.cp(src_path, dest_dir.join("0.jpg"))
          copied += 1
        else
          puts "  Source not found: #{src_path}"
        end
      end

      ex = Exercise.find_by(name: name)
      unless ex
        puts "  Not in DB: #{name}"
        next
      end

      local_url = "/exercise-images/db/#{slug}/0.jpg"
      ex.update_column(:image_url, local_url)
      puts "  #{name} → #{local_url}"
      db_updated += 1
    end

    puts "\nDone. Copied: #{copied}, DB updated: #{db_updated}."
  end

  desc "Sync gif_url and instructions from ExerciseDB, matching by image_url directory name"
  task sync_from_exercisedb: :environment do
    puts "Fetching full exercise data from ExerciseDB..."
    full_map = ExerciseDbService.fetch_full_map

    if full_map.empty?
      puts "Warning: ExerciseDB returned no data. Check connectivity."
      next
    end

    puts "Found #{full_map.size} exercises in ExerciseDB."
    updated = 0
    skipped = 0

    Exercise.find_each do |exercise|
      next unless exercise.image_url.present?

      dir_name   = exercise.image_url.split("/")[-2].to_s
      search_key = dir_name.downcase.gsub(/[-_]/, " ").gsub(/\s+/, " ").strip
      data       = full_map[search_key]

      unless data
        puts "  Skipped (no match): #{exercise.name} [#{search_key}]"
        skipped += 1
        next
      end

      exercise.update_columns(gif_url: data[:gif_url], instructions: data[:instructions])
      puts "  Updated: #{exercise.name}"
      updated += 1
    end

    puts "\nDone. Updated: #{updated}, Skipped: #{skipped}"
  end

  desc "Sync exercise GIF images from ExerciseDB public API"
  task sync_images: :environment do
    puts "Fetching exercise data from ExerciseDB..."
    gif_map = ExerciseDbService.fetch_gif_map

    if gif_map.empty?
      puts "Warning: ExerciseDB returned no data. Check connectivity."
      next
    end

    puts "Found #{gif_map.size} exercises in ExerciseDB."
    updated = 0
    skipped = 0

    Exercise.find_each do |exercise|
      gif_url = ExerciseDbService.gif_url_for(exercise.name, gif_map)
      if gif_url
        exercise.update_column(:image_url, gif_url)
        puts "  Updated: #{exercise.name} -> #{gif_url}"
        updated += 1
      else
        puts "  Skipped (no match): #{exercise.name}"
        skipped += 1
      end
    end

    puts "\nDone. Updated: #{updated}, Skipped: #{skipped}"
  end

  desc "Import ALL exercises and images from local free-exercise-db"
  task import_all: :environment do
    local_db = [
      Rails.root.join("..", "external", "free-exercise-db", "exercises"),
      Pathname.new("/external/free-exercise-db/exercises"),
    ].find { |p| p.directory? }

    unless local_db
      abort "ERROR: free-exercise-db not found. Expected at ../external/free-exercise-db/exercises"
    end

    dest_root = Rails.root.join("public", "exercise-images", "db")
    FileUtils.mkdir_p(dest_root)

    map_muscle = lambda do |primary|
      case primary.to_s.downcase
      when /chest/                                             then "chest"
      when /lats|middle back|lower back|traps|rhomboid|neck/  then "back"
      when /shoulder|delt/                                     then "shoulders"
      when /bicep|forearm/                                     then "biceps"
      when /tricep/                                            then "triceps"
      when /quad|hamstring|glute|calf|calves|abductor|adductor|hip|thigh/ then "legs"
      when /abdominal|oblique|core/                            then "core"
      end
    end

    map_equipment = lambda do |equip|
      e = equip.to_s.downcase
      if e.include?("body only") || e.match?(/\bbands?\b/) || e.blank?
        "bodyweight"
      elsif e.include?("dumbbell")
        "dumbbell"
      elsif e.include?("barbell") || e.include?("e-z curl")
        "barbell"
      elsif e.include?("cable")
        "cable"
      elsif e.include?("machine")
        "machine"
      elsif e.include?("cardio") || e.include?("treadmill") || e.include?("elliptic")
        "cardio"
      else
        "gym"
      end
    end

    map_category = lambda do |cat, muscle_group|
      c = cat.to_s.downcase
      if c.match?(/strength|powerlifting|strongman|olympic/)
        "musculacao"
      elsif c.include?("cardio")
        "cardio"
      elsif c.include?("plyometric")
        "hiit"
      elsif c.include?("stretching")
        "funcional"
      else
        muscle_group ? "musculacao" : "funcional"
      end
    end

    json_files = Dir.glob("#{local_db}/*.json").sort
    puts "Found #{json_files.size} exercise JSONs in #{local_db}"
    puts "Existing exercises in DB: #{Exercise.count}"

    imported      = 0
    images_copied = 0
    errors        = 0

    json_files.each do |json_path|
      data = JSON.parse(File.read(json_path)) rescue next

      name = data["name"].to_s.strip
      next if name.blank?
      next if Exercise.exists?(name: name)

      muscle_group   = map_muscle.call(Array(data["primaryMuscles"]).first.to_s)
      equipment_type = map_equipment.call(data["equipment"].to_s)
      exercise_type  = map_category.call(data["category"].to_s, muscle_group)
      difficulty     = data["level"] == "expert" ? "advanced" : (data["level"].presence || "intermediate")
      home_compat    = data["equipment"].to_s.downcase.match?(/body only|bands?/)
      instructions_text = Array(data["instructions"]).join("\n")
      description       = Array(data["instructions"]).first.to_s[0..249].presence || name

      first_img = Array(data["images"]).first
      image_url = nil
      if first_img.present?
        src = local_db.join(first_img)
        dst = dest_root.join(first_img)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst) unless File.exist?(dst)
          images_copied += 1
          image_url = "/exercise-images/db/#{first_img}"
        end
      end

      exercise = Exercise.new(
        name:            name,
        exercise_type:   exercise_type,
        equipment_type:  equipment_type,
        difficulty:      difficulty,
        home_compatible: home_compat,
        instructions:    instructions_text.presence,
        description:     description,
      )
      exercise.muscle_group = muscle_group if muscle_group
      exercise.image_url    = image_url    if image_url

      if exercise.save
        imported += 1
        print "." if (imported % 50).zero?
      else
        puts "\n  SKIP '#{name}': #{exercise.errors.full_messages.join(', ')}"
        errors += 1
      end
    end

    puts "\n\nDone!"
    puts "  New exercises imported: #{imported}"
    puts "  Images copied:          #{images_copied}"
    puts "  Validation errors:      #{errors}"
    puts "  Total exercises in DB:  #{Exercise.count}"
    puts ""
    puts "Chest exercises:     #{Exercise.where(muscle_group: 'chest').count}"
    puts "Back exercises:      #{Exercise.where(muscle_group: 'back').count}"
    puts "Shoulder exercises:  #{Exercise.where(muscle_group: 'shoulders').count}"
    puts "Biceps exercises:    #{Exercise.where(muscle_group: 'biceps').count}"
    puts "Triceps exercises:   #{Exercise.where(muscle_group: 'triceps').count}"
    puts "Legs exercises:      #{Exercise.where(muscle_group: 'legs').count}"
    puts "Core exercises:      #{Exercise.where(muscle_group: 'core').count}"
    puts "Cardio exercises:    #{Exercise.where(exercise_type: 'cardio').count}"
    puts "HIIT exercises:      #{Exercise.where(exercise_type: 'hiit').count}"
  end

  desc "Replace or remove workout_day_exercises linked to gym exercises without valid GIFs"
  task clean_gifless_wdes: :environment do
    audit    = ExerciseGifAuditJob.new
    replaced = 0
    removed  = 0

    WorkoutDayExercise
      .joins(:exercise)
      .where(
        "(exercises.exercise_type = 'musculacao' OR exercises.equipment_type IN ('gym','dumbbell','barbell','cable','machine'))" \
        " AND (exercises.gif_url IS NULL OR exercises.gif_url NOT LIKE '/exercise-images/%')"
      )
      .find_each do |wde|
        exercise = wde.exercise
        if (equiv = audit.send(:find_equivalent, exercise))
          wde.update!(exercise_id: equiv.id)
          puts "  Replaced: #{exercise.name} → #{equiv.name} [wde #{wde.id}]"
          replaced += 1
        else
          puts "  Removed: #{exercise.name} [wde #{wde.id}] (no equivalent)"
          wde.destroy
          removed += 1
        end
      end

    puts "\nDone. Replaced: #{replaced}, Removed: #{removed}"
  end

  desc "Fix image_url for existing seeded exercises and copy missing images"
  task fix_seed_images: :environment do
    local_db = [
      Rails.root.join("..", "external", "free-exercise-db", "exercises"),
      Pathname.new("/external/free-exercise-db/exercises"),
    ].find { |p| p.directory? }

    dest_root = Rails.root.join("public", "exercise-images", "db")
    copied    = 0
    updated   = 0

    SLUG_MAP.each do |exercise_name, slug|
      exercise = Exercise.find_by(name: exercise_name)
      next unless exercise

      expected_url = "/exercise-images/db/#{slug}/0.jpg"

      if local_db
        src = local_db.join(slug, "0.jpg")
        dst = dest_root.join(slug, "0.jpg")
        if File.exist?(src) && !File.exist?(dst)
          FileUtils.mkdir_p(dest_root.join(slug))
          FileUtils.cp(src, dst)
          copied += 1
        end
      end

      if exercise.image_url != expected_url
        exercise.update_column(:image_url, expected_url)
        updated += 1
        puts "  Fixed: #{exercise_name} → #{expected_url}"
      end
    end

    puts "\nDone. Images copied: #{copied}, image_url updated: #{updated}."
  end
end
