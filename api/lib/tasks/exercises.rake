require "net/http"
require "json"

namespace :exercises do
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
