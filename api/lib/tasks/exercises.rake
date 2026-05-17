require "net/http"
require "json"

BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"

IMAGE_MAP = {
  "Abdominal Bicicleta"      => "#{BASE}/Air_Bike/0.jpg",
  "Afundo Reverso"           => "#{BASE}/Crossover_Reverse_Lunge/0.jpg",
  "Agachamento Isométrico"   => "#{BASE}/Barbell_Squat/0.jpg",
  "Agachamento com Salto"    => "#{BASE}/Freehand_Jump_Squat/0.jpg",
  "Arremesso de Medicine Ball" => "#{BASE}/Backward_Medicine_Ball_Throw/0.jpg",
  "Bicicleta"                => "#{BASE}/Air_Bike/0.jpg",
  "Burpee"                   => "#{BASE}/Freehand_Jump_Squat/0.jpg",
  "Caminhada Moderada"       => "#{BASE}/Farmers_Walk/0.jpg",
  "Caminhada em Inclinação"  => "#{BASE}/Bodyweight_Walking_Lunge/0.jpg",
  "Corda Naval"              => "#{BASE}/Battling_Ropes/0.jpg",
  "Corrida Estacionária"     => "#{BASE}/Mountain_Climbers/0.jpg",
  "Corrida Esteira"          => "#{BASE}/Jogging_Treadmill/0.jpg",
  "Corrida Rua"              => "#{BASE}/Jogging_Treadmill/0.jpg",
  "Elevação Pélvica"         => "#{BASE}/Barbell_Hip_Thrust/0.jpg",
  "Elíptico"                 => "#{BASE}/Elliptical_Trainer/0.jpg",
  "Escalador"                => "#{BASE}/Mountain_Climbers/0.jpg",
  "Mountain Climber"         => "#{BASE}/Mountain_Climbers/0.jpg",
  "Nado Livre"               => "#{BASE}/Barbell_Deadlift/0.jpg",
  "Panturrilha em Pé"        => "#{BASE}/Calf_Raise_On_A_Dumbbell/0.jpg",
  "Polichinelo"              => "#{BASE}/Arm_Circles/0.jpg",
  "Ponte Unilateral"         => "#{BASE}/Butt_Lift_Bridge/0.jpg",
  "Pular Corda"              => "#{BASE}/Battling_Ropes/0.jpg",
  "Remada no TRX"            => "#{BASE}/Alternating_Renegade_Row/0.jpg",
  "Remo Ergômetro"           => "#{BASE}/Bent_Over_Barbell_Row/0.jpg",
  "Salto na Caixa"           => "#{BASE}/Front_Box_Jump/0.jpg",
  "Swing com Kettlebell"     => "#{BASE}/One-Arm_Kettlebell_Swings/0.jpg",
  "Tríceps no Banco"         => "#{BASE}/Bench_Dips/0.jpg",
  "Borboleta"                => "#{BASE}/Barbell_Deadlift/0.jpg",
}.freeze

namespace :exercises do
  desc "Fill missing image_url for exercises using free-exercise-db mappings"
  task fill_images: :environment do
    updated = 0
    IMAGE_MAP.each do |name, url|
      ex = Exercise.find_by(name: name)
      unless ex
        puts "  Not found: #{name}"
        next
      end
      next if ex.image_url.present?
      ex.update_column(:image_url, url)
      puts "  Updated: #{name}"
      updated += 1
    end
    puts "\nDone. #{updated} exercises updated."
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
      # Extract English name from image_url path:
      #   ".../Barbell_Bench_Press_-_Medium_Grip/0.jpg" → "barbell bench press medium grip"
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
