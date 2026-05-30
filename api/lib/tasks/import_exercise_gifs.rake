namespace :exercises do
  desc "Import GIFs from gifdotreino into the exercise database. Set GIFDOTREINO_PATH to the source folder."
  task import_gifdotreino: :environment do
    source_dir = ENV.fetch("GIFDOTREINO_PATH") do
      abort "[import_gifdotreino] Missing GIFDOTREINO_PATH. Example:\n" \
            "  rake exercises:import_gifdotreino GIFDOTREINO_PATH=/path/to/gifdotreino"
    end

    puts "[import_gifdotreino] Starting import from: #{source_dir}"
    puts "[import_gifdotreino] Destination: #{Rails.root.join('public/exercise-images/gifdotreino')}"
    puts ""

    report = ExerciseAssetImporter.new(source_dir: source_dir).call

    puts ""
    puts "=" * 50
    puts "IMPORT REPORT"
    puts "=" * 50
    puts "  CSV rows processed : #{report[:total_csv_rows]}"
    puts "  GIF files found    : #{report[:gif_files_found]}"
    puts "  GIF files missing  : #{report[:gif_files_missing]}"
    puts "  Exercises updated  : #{report[:exercises_updated]}"
    puts "  Exercises created  : #{report[:exercises_created]}"
    puts "  Exercises skipped  : #{report[:exercises_skipped]}"
    puts ""
    puts "  Full report saved to: tmp/import_gifdotreino_report.json"
    puts "=" * 50

    if report[:gifs_missing].any?
      puts "\nMISSING GIF FILES (#{report[:gifs_missing].size}):"
      report[:gifs_missing].first(10).each { |m| puts "  - #{m[:name]}" }
      puts "  ... (see report JSON for full list)" if report[:gifs_missing].size > 10
    end
  end
end
