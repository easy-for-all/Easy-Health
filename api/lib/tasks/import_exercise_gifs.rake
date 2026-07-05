namespace :exercises do
  # Runs on the production server where GIFs are already in public/exercise-images/gifdotreino/
  # (copied via rsync). No CSV needed — derives exercise info from folder/filename structure.
  desc "Link already-processed gifdotreino GIFs to exercises (production, no CSV required)"
  task link_gifdotreino: :environment do
    report = ExerciseCatalog::GifdotreinoCatalog.new.sync!

    puts ""
    puts "=" * 50
    puts "GIFDOTREINO LINK REPORT"
    puts "=" * 50
    puts "  GIF files scanned  : #{report[:total_gifs]}"
    puts "  Exercises updated  : #{report[:updated]}"
    puts "  Exercises created  : #{report[:created]}"
    puts "  Exercises skipped  : #{report[:skipped]}"
    puts "  Errors             : #{report[:errors].size}"
    puts "=" * 50

    report[:errors].first(10).each do |error|
      puts "  [SKIP] #{error[:path]}: #{error[:error]}"
    end
    puts "  ... (#{report[:errors].size - 10} more)" if report[:errors].size > 10
  end

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

  desc "Delete exercises that are not from /exercise-images/gifdotreino/*.gif. DRY_RUN=1 by default; set DRY_RUN=0 CONFIRM_PURGE=DELETE_NON_GIFDOTREINO to apply."
  task purge_non_gifdotreino: :environment do
    dry_run = ENV.fetch("DRY_RUN", "1") != "0"

    unless dry_run || ENV["CONFIRM_PURGE"] == "DELETE_NON_GIFDOTREINO"
      abort "[purge_non_gifdotreino] Refusing destructive purge. Re-run with DRY_RUN=0 CONFIRM_PURGE=DELETE_NON_GIFDOTREINO"
    end

    report = ExerciseCatalog::GifdotreinoCatalog.new.purge_non_gifdotreino!(dry_run: dry_run)

    puts ""
    puts "=" * 50
    puts dry_run ? "PURGE NON-GIFDOTREINO DRY RUN" : "PURGE NON-GIFDOTREINO REPORT"
    puts "=" * 50
    report.each do |key, value|
      puts "  #{key.to_s.ljust(34)} #{value}"
    end
    puts "=" * 50
  end
end
