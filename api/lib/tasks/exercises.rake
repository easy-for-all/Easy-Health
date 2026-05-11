require "net/http"
require "json"

namespace :exercises do
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
