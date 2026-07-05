require "csv"
require "fileutils"
require "find"
require "json"

class ExerciseAssetImporter
  DEST_DIR = Rails.root.join("public", "exercise-images", "gifdotreino")

  MUSCLE_MAP = {
    "Peitoral"        => { muscle_group: "chest",     exercise_type: "musculacao" },
    "Costas"          => { muscle_group: "back",      exercise_type: "musculacao" },
    "Ombros"          => { muscle_group: "shoulders", exercise_type: "musculacao" },
    "Bíceps"          => { muscle_group: "biceps",    exercise_type: "musculacao" },
    "Tríceps"         => { muscle_group: "triceps",   exercise_type: "musculacao" },
    "Pernas"          => { muscle_group: "legs",      exercise_type: "musculacao" },
    "Glúteos"         => { muscle_group: "glutes",    exercise_type: "musculacao" },
    "Panturrilhas"    => { muscle_group: "calves",    exercise_type: "musculacao" },
    "Trapézio"        => { muscle_group: "trapezius", exercise_type: "musculacao" },
    "Eretor Lombar"   => { muscle_group: "back",      exercise_type: "musculacao" },
    "Antebraços"      => { muscle_group: "forearms",  exercise_type: "musculacao" },
    "Calistenia"      => { muscle_group: "core",      exercise_type: "funcional"  },
    "Funcional e HIT" => { muscle_group: "core",      exercise_type: "funcional"  },
    "Mobilidade"      => { muscle_group: "core",      exercise_type: "funcional"  },
    "Crossfit"        => { muscle_group: "core",      exercise_type: "hiit"       },
    "Cardio"          => { muscle_group: nil,          exercise_type: "cardio"    }
  }.freeze

  def initialize(source_dir:)
    @source_dir = Pathname.new(source_dir)
    @csv_path   = @source_dir.join("exercicios.csv")
    @stats = {
      total_csv_rows:    0,
      gif_files_found:   0,
      gif_files_missing: 0,
      exercises_updated: 0,
      exercises_created: 0,
      exercises_skipped: 0,
      gifs_missing:      []
    }
  end

  def call
    validate_source!
    load_exercise_index
    build_file_index
    rows = parse_csv
    Rails.logger.info "[ExerciseAssetImporter] Processing #{rows.size} rows from CSV"

    rows.each { |row| process_row(row) }
    report = generate_report
    Rails.logger.info "[ExerciseAssetImporter] Done. #{@stats.slice(:exercises_created, :exercises_updated, :exercises_skipped).inspect}"
    report
  end

  private

  def validate_source!
    raise "Source directory not found: #{@source_dir}" unless @source_dir.exist?
    raise "exercicios.csv not found in #{@source_dir}" unless @csv_path.exist?
  end

  # Lookup: normalized_name => Exercise
  def load_exercise_index
    @exercise_index = {}
    Exercise.all.each do |ex|
      @exercise_index[normalize(ex.name)] = ex
      @exercise_index[normalize(ex.name_en.to_s)] = ex if ex.name_en.present?
    end
  end

  # Build a lookup of all real GIF files on disk: normalized_name => real_path
  #
  # The ZIP was extracted with CP437 byte-to-Unicode conversion applied to UTF-8 filenames,
  # producing garbled names on the filesystem (e.g. `ç` → `├º`).
  # We reverse this: each garbled Unicode char → CP437 byte → re-read bytes as UTF-8.
  def build_file_index
    @file_index = {}
    Find.find(@source_dir.to_s) do |path|
      next unless File.file?(path) && path.downcase.end_with?(".gif")
      raw_name = File.basename(path, File.extname(path))
      fixed    = fix_garbled_encoding(raw_name)
      key      = normalize(fixed)
      @file_index[key] ||= path
    end
    Rails.logger.info "[ExerciseAssetImporter] Indexed #{@file_index.size} GIF files from filesystem"
  end

  # Reverses the CP437 mis-encoding: each Unicode char is mapped back to its CP437 byte,
  # then the resulting byte sequence is re-interpreted as UTF-8.
  def fix_garbled_encoding(str)
    bytes = str.chars.flat_map do |c|
      c.encode("IBM437").b.bytes
    rescue Encoding::UndefinedConversionError
      c.encode("UTF-8").b.bytes
    end
    bytes.pack("C*").force_encoding("UTF-8").scrub("?")
  rescue
    str
  end

  def parse_csv
    raw  = @csv_path.read(encoding: "bom|utf-8")
    rows = CSV.parse(raw, headers: true, liberal_parsing: true)
    @stats[:total_csv_rows] = rows.size
    rows
  end

  def process_row(row)
    name        = row[0].to_s.strip
    group_pt    = row[1].to_s.strip
    gif_rel     = row[2].to_s.strip
    description = row[3].to_s.strip

    return if name.blank? || gif_rel.blank?

    # Find the actual file using the filesystem index (encoding-safe)
    exercise_name_from_csv = File.basename(gif_rel, File.extname(gif_rel))
    real_path = @file_index[normalize(exercise_name_from_csv)]

    unless real_path
      @stats[:gif_files_missing] += 1
      @stats[:gifs_missing] << { name: name, path: gif_rel }
      Rails.logger.warn "[ExerciseAssetImporter] GIF not found for: #{name}"
      return
    end

    @stats[:gif_files_found] += 1
    mapping    = MUSCLE_MAP[group_pt] || { muscle_group: "core", exercise_type: "funcional" }
    group_slug = to_kebab(group_pt)
    file_slug  = "#{to_kebab(name)}.gif"
    dest_dir   = DEST_DIR.join(group_slug)
    dest_path  = dest_dir.join(file_slug)
    gif_url    = "/exercise-images/gifdotreino/#{group_slug}/#{file_slug}"

    FileUtils.mkdir_p(dest_dir)
    FileUtils.cp(real_path, dest_path.to_s) unless dest_path.exist?

    exercise = find_exercise(name)
    if exercise
      attrs = { gif_url: gif_url }
      attrs[:gif_path] = dest_path.to_s if exercise_column?(:gif_path)
      attrs[:image_url] = nil if exercise_column?(:image_url)
      attrs[:image_fallback_url] = nil if exercise_column?(:image_fallback_url)
      attrs[:source_dataset] = "gifdotreino" if exercise_column?(:source_dataset)
      exercise.update_columns(attrs)
      @stats[:exercises_updated] += 1
    else
      attrs = {
        name:           name,
        exercise_type:  mapping[:exercise_type],
        muscle_group:   mapping[:muscle_group],
        equipment_type: "gym",
        difficulty:     "intermediate",
        gif_url:        gif_url,
        description:    description.truncate(500),
      }
      attrs[:difficulty_level] = "intermediate" if exercise_column?(:difficulty_level)
      attrs[:gif_path] = dest_path.to_s if exercise_column?(:gif_path)
      attrs[:source_dataset] = "gifdotreino" if exercise_column?(:source_dataset)
      Exercise.create!(attrs)
      @stats[:exercises_created] += 1
    end
  rescue => e
    Rails.logger.error "[ExerciseAssetImporter] Error processing '#{name}': #{e.message}"
    @stats[:exercises_skipped] += 1
  end

  def find_exercise(name)
    @exercise_index[normalize(name)]
  end

  def exercise_column?(name)
    Exercise.column_names.include?(name.to_s)
  end

  def normalize(name)
    name.to_s
        .unicode_normalize(:nfkd)
        .encode("ASCII", replace: "")
        .downcase
        .gsub(/[^a-z0-9\s]/, "")
        .squeeze(" ")
        .strip
  end

  def to_kebab(name)
    normalize(name).gsub(/\s+/, "-")
  end

  def generate_report
    report = {
      generated_at:      Time.current.iso8601,
      source_dir:        @source_dir.to_s,
      total_csv_rows:    @stats[:total_csv_rows],
      gif_files_found:   @stats[:gif_files_found],
      gif_files_missing: @stats[:gif_files_missing],
      exercises_updated: @stats[:exercises_updated],
      exercises_created: @stats[:exercises_created],
      exercises_skipped: @stats[:exercises_skipped],
      gifs_missing:      @stats[:gifs_missing]
    }

    report_path = Rails.root.join("tmp", "import_gifdotreino_report.json")
    report_path.write(JSON.pretty_generate(report))
    Rails.logger.info "[ExerciseAssetImporter] Report saved to #{report_path}"
    report
  end
end
