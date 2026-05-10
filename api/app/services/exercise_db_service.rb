class ExerciseDbService
  BASE_URL = "https://exercisedb-api.vercel.app/api/v1".freeze
  LIMIT = 1300

  # Returns a hash: { normalized_name => gif_url }
  def self.fetch_gif_map
    new.fetch_gif_map
  end

  def fetch_gif_map
    exercises = fetch_all_exercises
    exercises.each_with_object({}) do |ex, map|
      name = ex["name"].to_s.downcase.strip
      map[name] = ex["gifUrl"]
    end
  end

  # Tries to find a gif_url for a given exercise name.
  # Falls back to nil if not found.
  def self.gif_url_for(exercise_name, gif_map)
    key = exercise_name.to_s.downcase.strip
    gif_map[key]
  end

  private

  def fetch_all_exercises
    uri = URI("#{BASE_URL}/exercises?offset=0&limit=#{LIMIT}")
    response = Net::HTTP.get_response(uri)
    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.is_a?(Array) ? data : (data["exercises"] || data["data"] || [])
  rescue StandardError => e
    Rails.logger.error "ExerciseDbService error: #{e.message}"
    []
  end
end
