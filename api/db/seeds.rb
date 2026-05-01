exercises = [
  # Musculação — peito
  { name: "Push-up",          exercise_type: "musculacao", muscle_group: "chest",     description: "Classic push-up. Keep your core tight." },
  { name: "Bench Press",      exercise_type: "musculacao", muscle_group: "chest",     description: "Lie on bench, lower bar to chest, press up." },
  # Musculação — costas
  { name: "Pull-up",          exercise_type: "musculacao", muscle_group: "back",      description: "Hang from bar, pull chest to bar." },
  { name: "Bent-over Row",    exercise_type: "musculacao", muscle_group: "back",      description: "Hinge at hips, row barbell to lower chest." },
  # Musculação — ombros
  { name: "Overhead Press",   exercise_type: "musculacao", muscle_group: "shoulders", description: "Press barbell or dumbbells overhead." },
  { name: "Lateral Raise",    exercise_type: "musculacao", muscle_group: "shoulders", description: "Raise dumbbells to shoulder height." },
  # Musculação — bíceps
  { name: "Bicep Curl",       exercise_type: "musculacao", muscle_group: "biceps",    description: "Curl dumbbells with controlled motion." },
  { name: "Hammer Curl",      exercise_type: "musculacao", muscle_group: "biceps",    description: "Curl with neutral grip." },
  # Musculação — tríceps
  { name: "Tricep Dip",       exercise_type: "musculacao", muscle_group: "triceps",   description: "Lower body using parallel bars or a chair." },
  { name: "Skull Crusher",    exercise_type: "musculacao", muscle_group: "triceps",   description: "Lower bar to forehead, extend arms." },
  # Musculação — pernas
  { name: "Squat",            exercise_type: "musculacao", muscle_group: "legs",      description: "Feet shoulder-width apart, squat to parallel." },
  { name: "Lunges",           exercise_type: "musculacao", muscle_group: "legs",      description: "Step forward and lower back knee to floor." },
  { name: "Deadlift",         exercise_type: "musculacao", muscle_group: "legs",      description: "Hinge at hips, lift barbell from floor." },
  # Musculação — core
  { name: "Plank",            exercise_type: "musculacao", muscle_group: "core",      description: "Hold push-up position for time." },
  { name: "Crunch",           exercise_type: "musculacao", muscle_group: "core",      description: "Curl shoulders toward knees." },
  # Cardio
  { name: "Pular Corda",      exercise_type: "cardio",     muscle_group: nil, description: "Jump rope at a steady pace for 3-5 minutes." },
  { name: "Remo Ergômetro",   exercise_type: "cardio",     muscle_group: nil, description: "Row on ergometer, maintain steady stroke rate." },
  { name: "Bicicleta",        exercise_type: "cardio",     muscle_group: nil, description: "Stationary or outdoor cycling at moderate intensity." },
  { name: "Elíptico",         exercise_type: "cardio",     muscle_group: nil, description: "Elliptical trainer, keep resistance moderate." },
  # HIIT
  { name: "Burpee",           exercise_type: "hiit",       muscle_group: nil, description: "Drop to push-up, jump up explosively. Full body." },
  { name: "Box Jump",         exercise_type: "hiit",       muscle_group: nil, description: "Explosive jump onto a box, step down to reset." },
  { name: "Mountain Climber", exercise_type: "hiit",       muscle_group: nil, description: "Plank position, drive knees alternately to chest." },
  { name: "Jump Squat",       exercise_type: "hiit",       muscle_group: nil, description: "Squat deep, then jump explosively off the floor." },
  # Funcional
  { name: "Kettlebell Swing", exercise_type: "funcional",  muscle_group: nil, description: "Hip hinge with explosive drive, swing to shoulder height." },
  { name: "TRX Row",          exercise_type: "funcional",  muscle_group: nil, description: "Bodyweight row on suspension straps, elbows wide." },
  { name: "Battle Ropes",     exercise_type: "funcional",  muscle_group: nil, description: "Alternating or simultaneous wave motion for 30-45s." },
  { name: "Med Ball Slam",    exercise_type: "funcional",  muscle_group: nil, description: "Raise medicine ball overhead, slam to floor forcefully." },
  # Corrida
  { name: "Corrida Esteira",  exercise_type: "corrida",    muscle_group: nil, description: "Run on treadmill at target pace, maintain form." },
  { name: "Corrida Rua",      exercise_type: "corrida",    muscle_group: nil, description: "Outdoor run, focus on breathing rhythm and pace." },
  # Natação
  { name: "Crawl",            exercise_type: "natacao",    muscle_group: nil, description: "Freestyle stroke, bilateral breathing every 3 strokes." },
  { name: "Borboleta",        exercise_type: "natacao",    muscle_group: nil, description: "Butterfly stroke, dolphin kick for propulsion." },
  # Caminhada
  { name: "Caminhada Moderada",    exercise_type: "caminhada", muscle_group: nil, description: "Brisk walk at 5-6 km/h for 30-45 minutes." },
  { name: "Caminhada Inclinação",  exercise_type: "caminhada", muscle_group: nil, description: "Walk uphill or on inclined treadmill for extra resistance." },
]

exercises.each { |e| Exercise.find_or_create_by!(name: e[:name]).update!(e) }
puts "#{Exercise.count} exercises seeded"

User.find_or_create_by(email: "test@example.com") do |u|
  u.name = "Test User"
  u.password = "password123"
  u.password_confirmation = "password123"
end
puts "Test user: test@example.com / password123"
