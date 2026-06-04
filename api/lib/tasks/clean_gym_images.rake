namespace :exercises do
  desc "Remove JPG image_url/image_fallback_url from gym/musculacao exercises when a GIF exists"
  task clean_gym_external_images: :environment do
    allowed_prefixes_without_gif = %w[/exercise-images/db/ /exercise-images/gifdotreino/]
    allowed_prefixes_with_gif    = %w[/exercise-images/gifdotreino/]
    gym_equipment     = %w[gym dumbbell barbell cable machine]

    scope = Exercise.where(exercise_type: "musculacao")
                    .or(Exercise.where(equipment_type: gym_equipment))

    total   = scope.count
    cleaned = 0

    scope.find_each do |ex|
      changed = false

      %i[image_url image_fallback_url].each do |field|
        val = ex.public_send(field)
        next if val.blank?

        allowed_prefixes = ex.gif_url.present? ? allowed_prefixes_with_gif : allowed_prefixes_without_gif
        next if allowed_prefixes.any? { |p| val.start_with?(p) }

        puts "  [clear] #{ex.name} | #{field}: #{val}"
        ex.assign_attributes(field => nil)
        changed = true
      end

      if changed
        ex.save!(validate: false)
        cleaned += 1
      end
    end

    puts "\nVerificados: #{total} | Limpos: #{cleaned}"
  end
end
