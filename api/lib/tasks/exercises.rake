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
end
