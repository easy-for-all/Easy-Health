namespace :exercises do
  # Runs on the production server where GIFs are already in public/exercise-images/gifdotreino/
  # (copied via rsync). No CSV needed — derives exercise info from folder/filename structure.
  desc "Link already-processed gifdotreino GIFs to exercises (production, no CSV required)"
  task link_gifdotreino: :environment do
    gif_dir = Rails.root.join("public", "exercise-images", "gifdotreino")

    unless gif_dir.exist?
      abort "[link_gifdotreino] Directory not found: #{gif_dir}\n" \
            "Run: docker cp <host_path>/gifdotreino/. <container>:/rails/public/exercise-images/gifdotreino/"
    end

    muscle_map = {
      "peitoral"        => { muscle_group: "chest",     exercise_type: "musculacao" },
      "costas"          => { muscle_group: "back",      exercise_type: "musculacao" },
      "ombros"          => { muscle_group: "shoulders", exercise_type: "musculacao" },
      "biceps"          => { muscle_group: "biceps",    exercise_type: "musculacao" },
      "triceps"         => { muscle_group: "triceps",   exercise_type: "musculacao" },
      "pernas"          => { muscle_group: "legs",      exercise_type: "musculacao" },
      "gluteos"         => { muscle_group: "glutes",    exercise_type: "musculacao" },
      "panturrilhas"    => { muscle_group: "calves",    exercise_type: "musculacao" },
      "trapezio"        => { muscle_group: "trapezius", exercise_type: "musculacao" },
      "eretor-lombar"   => { muscle_group: "back",      exercise_type: "musculacao" },
      "antebracos"      => { muscle_group: "forearms",  exercise_type: "musculacao" },
      "calistenia"      => { muscle_group: "core",      exercise_type: "funcional"  },
      "funcional-e-hit" => { muscle_group: "core",      exercise_type: "funcional"  },
      "mobilidade"      => { muscle_group: "core",      exercise_type: "funcional"  },
      "crossfit"        => { muscle_group: "core",      exercise_type: "hiit"       },
      "cardio"          => { muscle_group: nil,          exercise_type: "cardio"    }
    }

    normalize = ->(s) { s.to_s.downcase.gsub(/[^a-z0-9\s]/, "").squeeze(" ").strip }

    exercise_index = {}
    Exercise.all.each do |ex|
      exercise_index[normalize.(ex.name)]          = ex
      exercise_index[normalize.(ex.name_en.to_s)]  = ex if ex.name_en.present?
    end

    updated = 0
    created = 0
    skipped = 0

    puts "[link_gifdotreino] Scanning #{gif_dir}..."
    Dir.glob("#{gif_dir}/**/*.gif").sort.each do |gif_path|
      rel        = gif_path.delete_prefix("#{gif_dir}/")
      parts      = rel.split("/")
      next unless parts.size == 2

      group_slug = parts[0]
      name_slug  = File.basename(parts[1], ".gif")
      gif_url    = "/exercise-images/gifdotreino/#{group_slug}/#{name_slug}.gif"
      name_key   = name_slug.gsub("-", " ")
      mapping    = muscle_map[group_slug] || { muscle_group: "core", exercise_type: "funcional" }

      exercise = exercise_index[name_key]
      if exercise
        exercise.update_columns(gif_url: gif_url, gif_path: gif_path)
        exercise_index[name_key] = exercise
        updated += 1
      else
        display_name = name_slug.split("-").map(&:capitalize).join(" ")
        ex = Exercise.create!(
          name:           display_name,
          exercise_type:  mapping[:exercise_type],
          muscle_group:   mapping[:muscle_group],
          equipment_type: "gym",
          difficulty:     "intermediate",
          gif_url:        gif_url,
          gif_path:       gif_path,
          source_dataset: "gifdotreino"
        )
        exercise_index[name_key] = ex
        created += 1
      end
    rescue => e
      puts "  [SKIP] #{name_slug}: #{e.message}"
      skipped += 1
    end

    puts ""
    puts "=" * 50
    puts "LINK REPORT"
    puts "=" * 50
    puts "  Exercises updated  : #{updated}"
    puts "  Exercises created  : #{created}"
    puts "  Exercises skipped  : #{skipped}"
    puts "=" * 50
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
end
