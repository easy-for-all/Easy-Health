LOCAL_IMG = "/exercise-images/db"

exercises = [
  # Musculação — peito
  { name: "Flexão de Braço",    exercise_type: "musculacao", muscle_group: "chest",     equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Pushups/0.jpg",                                description: "Apoie as mãos no chão na largura dos ombros e desça o peito até próximo ao chão, mantendo o core firme." },
  { name: "Supino",             exercise_type: "musculacao", muscle_group: "chest",     equipment_type: "barbell",    difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Barbell_Bench_Press_-_Medium_Grip/0.jpg",     description: "Deite no banco, desça a barra até o peito e empurre de volta para cima de forma controlada." },
  # Musculação — costas
  { name: "Barra Fixa",         exercise_type: "musculacao", muscle_group: "back",      equipment_type: "bodyweight", difficulty: "intermediate",  home_compatible: true,  image_url: "#{LOCAL_IMG}/Pullups/0.jpg",                               description: "Suspenda-se na barra com as palmas para frente e puxe o peito até a barra." },
  { name: "Remada Curvada",     exercise_type: "musculacao", muscle_group: "back",      equipment_type: "barbell",    difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Bent_Over_Barbell_Row/0.jpg",                 description: "Incline o tronco para frente e puxe a barra em direção ao abdômen inferior, mantendo as costas retas." },
  # Musculação — ombros
  { name: "Desenvolvimento",    exercise_type: "musculacao", muscle_group: "shoulders", equipment_type: "barbell",    difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Barbell_Shoulder_Press/0.jpg",                description: "Empurre a barra ou halteres para cima da cabeça com os braços estendidos." },
  { name: "Elevação Lateral",   exercise_type: "musculacao", muscle_group: "shoulders", equipment_type: "dumbbell",   difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Lateral_Raise_-_With_Bands/0.jpg",            description: "Eleve os halteres lateralmente até a altura dos ombros, mantendo leve flexão nos cotovelos." },
  # Musculação — bíceps
  { name: "Rosca Direta",       exercise_type: "musculacao", muscle_group: "biceps",    equipment_type: "dumbbell",   difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Barbell_Curl/0.jpg",                          description: "Flexione os cotovelos levantando os halteres em movimento controlado, sem balançar o corpo." },
  { name: "Rosca Martelo",      exercise_type: "musculacao", muscle_group: "biceps",    equipment_type: "dumbbell",   difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Alternate_Hammer_Curl/0.jpg",                 description: "Segure os halteres com pegada neutra (palmas voltadas uma para a outra) e faça a rosca." },
  # Musculação — tríceps
  { name: "Mergulho no Banco",  exercise_type: "musculacao", muscle_group: "triceps",   equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Bench_Dips/0.jpg",                            description: "Apoie as mãos em um banco atrás do corpo e desça dobrando os cotovelos, depois empurre de volta." },
  { name: "Tríceps Francês",    exercise_type: "musculacao", muscle_group: "triceps",   equipment_type: "dumbbell",   difficulty: "intermediate",  home_compatible: true,  image_url: "#{LOCAL_IMG}/Band_Skull_Crusher/0.jpg",                    description: "Deite e segure a barra acima da testa, dobrando os cotovelos; estenda os braços para cima." },
  # Musculação — pernas
  { name: "Agachamento",        exercise_type: "musculacao", muscle_group: "legs",      equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Barbell_Squat/0.jpg",                         description: "Pés na largura dos ombros, desça até as coxas ficarem paralelas ao chão, mantendo o tronco ereto." },
  { name: "Avanço",             exercise_type: "musculacao", muscle_group: "legs",      equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Barbell_Lunge/0.jpg",                         description: "Dê um passo à frente e desça o joelho de trás próximo ao chão; empurre de volta à posição inicial." },
  { name: "Levantamento Terra", exercise_type: "musculacao", muscle_group: "legs",      equipment_type: "barbell",    difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Barbell_Deadlift/0.jpg",                      description: "Com os pés na largura dos quadris, incline o quadril e levante a barra do chão mantendo a coluna neutra." },
  # Musculação — core
  { name: "Prancha",            exercise_type: "musculacao", muscle_group: "core",      equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Plank/0.jpg",                                 description: "Apoie nos antebraços e pés; mantenha o corpo reto como uma prancha pelo tempo determinado." },
  { name: "Abdominal",          exercise_type: "musculacao", muscle_group: "core",      equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/3_4_Sit-Up/0.jpg",                            description: "Deitado, leve os ombros em direção aos joelhos contraindo o abdômen; desça com controle." },
  # Cardio — máquinas
  { name: "Pular Corda",        exercise_type: "cardio",     muscle_group: nil,         equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Battling_Ropes/0.jpg",       description: "Salte a corda em ritmo constante por 3 a 5 minutos, mantendo os joelhos levemente flexionados." },
  { name: "Remo Ergômetro",     exercise_type: "cardio",     muscle_group: nil,         equipment_type: "cardio",     difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Bent_Over_Barbell_Row/0.jpg", description: "Remada no ergômetro: empurre com as pernas, recline o tronco e puxe o cabo até o abdômen." },
  { name: "Bicicleta",          exercise_type: "cardio",     muscle_group: nil,         equipment_type: "cardio",     difficulty: "beginner",      home_compatible: false, image_url: "#{LOCAL_IMG}/Air_Bike/0.jpg",              description: "Pedale em intensidade moderada na bike estacionária ou ao ar livre." },
  { name: "Elíptico",           exercise_type: "cardio",     muscle_group: nil,         equipment_type: "cardio",     difficulty: "beginner",      home_compatible: false, image_url: "#{LOCAL_IMG}/Elliptical_Trainer/0.jpg",   description: "Use o elíptico com resistência moderada, mantendo postura ereta e movimentos fluidos." },
  { name: "Simulador de Escada", exercise_type: "cardio",  muscle_group: nil, equipment_type: "cardio",     difficulty: "intermediate", home_compatible: false, image_url: "#{LOCAL_IMG}/Stairmaster/0.jpg",             description: "Use o simulador de escada (StairMaster) em ritmo constante, mantendo as costas eretas e os joelhos alinhados." },
  # HIIT
  { name: "Burpee",             exercise_type: "hiit",       muscle_group: nil,         equipment_type: "bodyweight", difficulty: "intermediate",  home_compatible: true,  image_url: "#{LOCAL_IMG}/Freehand_Jump_Squat/0.jpg",   description: "Abaixe para a posição de flexão, execute uma flexão, salte de volta e dê um salto explosivo com os braços acima." },
  { name: "Salto na Caixa",     exercise_type: "hiit",       muscle_group: nil,         equipment_type: "gym",        difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Front_Box_Jump/0.jpg",        description: "Salte explosivamente sobre uma caixa ou plataforma e desça com cuidado para recomeçar." },
  { name: "Escalador",          exercise_type: "hiit",       muscle_group: nil,         equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Mountain_Climbers/0.jpg",     description: "Na posição de prancha, leve os joelhos alternadamente em direção ao peito o mais rápido possível." },
  { name: "Agachamento com Salto", exercise_type: "hiit",   muscle_group: nil,          equipment_type: "bodyweight", difficulty: "intermediate",  home_compatible: true,  image_url: "#{LOCAL_IMG}/Freehand_Jump_Squat/0.jpg",   description: "Faça um agachamento profundo e, ao subir, salte explosivamente saindo do chão." },
  # Funcional
  { name: "Swing com Kettlebell", exercise_type: "funcional", muscle_group: nil,        equipment_type: "gym",        difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/One-Arm_Kettlebell_Swings/0.jpg",   description: "Dobre o quadril com o kettlebell entre as pernas e projete-o à altura dos ombros usando a força dos glúteos." },
  { name: "Remada no TRX",     exercise_type: "funcional",  muscle_group: nil,          equipment_type: "gym",        difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Alternating_Renegade_Row/0.jpg",    description: "Segure as alças do TRX inclinado para trás e puxe o corpo em direção às alças, abrindo os cotovelos." },
  { name: "Corda Naval",        exercise_type: "funcional",  muscle_group: nil,         equipment_type: "gym",        difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Battling_Ropes/0.jpg",              description: "Segure as extremidades da corda e faça ondas alternadas ou simultâneas por 30 a 45 segundos." },
  { name: "Arremesso de Medicine Ball", exercise_type: "funcional", muscle_group: nil,  equipment_type: "gym",        difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Backward_Medicine_Ball_Throw/0.jpg", description: "Levante a medicine ball acima da cabeça e arremesse-a contra o chão com força total." },
  # Corrida
  { name: "Corrida Esteira",    exercise_type: "corrida",    muscle_group: nil,         equipment_type: "cardio",     difficulty: "beginner",      home_compatible: false, image_url: "#{LOCAL_IMG}/Jogging_Treadmill/0.jpg",     description: "Corra na esteira no ritmo alvo, mantendo a postura ereta e a respiração controlada." },
  { name: "Corrida Rua",        exercise_type: "corrida",    muscle_group: nil,         equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Jogging_Treadmill/0.jpg",     description: "Corrida ao ar livre com foco no ritmo respiratório e na cadência dos passos." },
  # Natação
  { name: "Nado Livre",         exercise_type: "natacao",    muscle_group: nil,         equipment_type: "cardio",     difficulty: "intermediate",  home_compatible: false, image_url: "#{LOCAL_IMG}/Barbell_Deadlift/0.jpg",      description: "Nado crawl com respiração bilateral a cada 3 braçadas." },
  { name: "Borboleta",          exercise_type: "natacao",    muscle_group: nil,         equipment_type: "cardio",     difficulty: "advanced",      home_compatible: false, image_url: "#{LOCAL_IMG}/Barbell_Deadlift/0.jpg",      description: "Nado borboleta com batida de golfinho para propulsão; mantenha o ritmo dos braços sincronizado." },
  # Caminhada
  { name: "Caminhada Moderada",    exercise_type: "caminhada", muscle_group: nil,       equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: false, image_url: "#{LOCAL_IMG}/Farmers_Walk/0.jpg",           description: "Caminhada em ritmo ativo entre 5 e 6 km/h por 30 a 45 minutos." },
  { name: "Caminhada em Inclinação", exercise_type: "caminhada", muscle_group: nil,     equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: false, image_url: "#{LOCAL_IMG}/Bodyweight_Walking_Lunge/0.jpg", description: "Caminhe em subida ou esteira inclinada para aumentar a resistência e o gasto calórico." },

  # Peso corporal — sem equipamentos (todos home_compatible)
  { name: "Polichinelo",              exercise_type: "hiit",       muscle_group: nil,    equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Arm_Circles/0.jpg",              description: "De pé, salte abrindo pernas e braços simultaneamente e volte à posição inicial em ritmo rápido." },
  { name: "Mountain Climber",         exercise_type: "hiit",       muscle_group: "core", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Mountain_Climbers/0.jpg",        description: "Na posição de prancha alta, leve os joelhos alternadamente em direção ao peito em ritmo acelerado." },
  { name: "Panturrilha em Pé",        exercise_type: "musculacao", muscle_group: "legs", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Calf_Raise_On_A_Dumbbell/0.jpg", description: "Em pé, eleve-se nas pontas dos pés contraindo as panturrilhas e desça de forma controlada." },
  { name: "Elevação Pélvica",         exercise_type: "musculacao", muscle_group: "legs", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Barbell_Hip_Thrust/0.jpg",       description: "Deitado, pés no chão, eleve o quadril contraindo os glúteos até o corpo formar uma linha reta." },
  { name: "Agachamento Isométrico",   exercise_type: "funcional",  muscle_group: "legs", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Barbell_Squat/0.jpg",            description: "Costas na parede, desça até 90° e mantenha a posição pelo tempo determinado sem subir." },
  { name: "Corrida Estacionária",     exercise_type: "cardio",     muscle_group: nil,    equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Mountain_Climbers/0.jpg",        description: "Corra no lugar levantando os joelhos acima da linha do quadril em ritmo moderado a intenso." },
  { name: "Tríceps no Banco",         exercise_type: "musculacao", muscle_group: "triceps", equipment_type: "bodyweight", difficulty: "beginner",   home_compatible: true,  image_url: "#{LOCAL_IMG}/Bench_Dips/0.jpg",               description: "Apoie as mãos em uma cadeira ou banco atrás do corpo e desça dobrando os cotovelos a 90°." },
  { name: "Ponte Unilateral",         exercise_type: "musculacao", muscle_group: "legs", equipment_type: "bodyweight", difficulty: "intermediate",  home_compatible: true,  image_url: "#{LOCAL_IMG}/Butt_Lift_Bridge/0.jpg",         description: "Deitado, uma perna estendida no ar, eleve o quadril usando apenas a perna apoiada no chão." },
  { name: "Abdominal Bicicleta",      exercise_type: "musculacao", muscle_group: "core", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Air_Bike/0.jpg",                  description: "Deitado com as mãos na cabeça, leve o cotovelo ao joelho oposto em movimento alternado." },
  { name: "Afundo Reverso",           exercise_type: "musculacao", muscle_group: "legs", equipment_type: "bodyweight", difficulty: "beginner",      home_compatible: true,  image_url: "#{LOCAL_IMG}/Crossover_Reverse_Lunge/0.jpg",  description: "Dê um passo para trás dobrando o joelho traseiro próximo ao chão; empurre de volta à posição inicial." },
]

exercises.each do |e|
  exercise = Exercise.find_or_initialize_by(name: e[:name])
  exercise.assign_attributes(e)
  exercise.save!
end
puts "#{Exercise.count} exercises seeded"

User.find_or_create_by(email: "test@example.com") do |u|
  u.name = "Test User"
  u.password = "password123"
  u.password_confirmation = "password123"
end
puts "Test user: test@example.com / password123"

# AI Prompt Versions
VALID_METHODS  = %w[full_body upper_lower ab abc ppl custom].freeze
VALID_GROUPS   = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze

workout_prompt_v1 = <<~PROMPT
  Você é um Coach Fitness especialista em prescrição personalizada de treino.
  Analise o perfil completo abaixo e retorne SOMENTE um JSON válido, sem texto adicional.

  ## IDENTIDADE DO USUÁRIO
  - Persona primária: {{persona}}
  - Archetype de treino: {{archetype}}
  - Padrão de comportamento: {{behavior}}
  - Nível: {{fitness_level}}
  - Objetivo: {{goal}}

  ## SCORES DE INTELIGÊNCIA FITNESS
  {{scores}}

  ## ESTRATÉGIA DEFINIDA PELO COACH ENGINE
  {{strategy}}

  ## LIMITAÇÕES FÍSICAS
  {{limitations}}

  ## EQUIPAMENTOS DISPONÍVEIS
  {{equipment}}

  ## EXERCÍCIOS PREFERIDOS
  {{preferred_exercises}}

  ## EXERCÍCIOS A EVITAR
  {{avoided_exercises}}

  ## HISTÓRICO RECENTE (últimas 5 sessões)
  {{recent_history}}

  ## EXERCÍCIOS DISPONÍVEIS NO SISTEMA (por grupo muscular)
  {{available_exercises}}

  ## REGRAS DE SEGURANÇA (OBRIGATÓRIAS)
  - NUNCA sugira exercícios avançados para persona beginner ou iniciante
  - NUNCA ignore as limitações físicas declaradas
  - NUNCA coloque mais de 5 exercícios por grupo muscular para iniciantes
  - NUNCA coloque o mesmo grupo muscular em dias consecutivos
  - SEMPRE inclua aquecimento para personas de risco alto
  - Respeite o foco corporal definido na estratégia (body_focus_priority)
  - Se behavior inclui "abandons_long_workouts", mantenha sessões curtas
  - Se behavior inclui "skips_cardio", não force cardio pesado

  ## REGRAS DE PRODUTO
  - Explique CLARAMENTE por que esse treino foi montado para esta persona específica
  - O campo personalization_reason DEVE referenciar a persona, archetype e behavior real do usuário
  - O campo user_explanation deve ser amigável e motivador, em português

  ## FORMATO DE RESPOSTA (JSON puro, sem markdown, sem texto fora do JSON)
  {
    "training_method": "#{VALID_METHODS.join(' | ')}",
    "plan_name": "Nome do Plano",
    "rationale": "Explicação técnica em português (2-3 frases)",
    "personalization_reason": "Montei este treino porque você [persona/archetype/behavior em linguagem humana]",
    "user_explanation": "Mensagem amigável para o usuário explicando o treino",
    "coach_notes": "Observações do coach para futuras adaptações",
    "week_structure": [
      { "name": "Nome do Dia", "muscle_groups": ["#{VALID_GROUPS.join('", "')}"] }
    ],
    "sets": 3,
    "reps": 10,
    "rest_seconds": 90,
    "progression_strategy": "Descrição da progressão semana a semana",
    "safety_notes": ["Nota de segurança 1", "Nota de segurança 2"]
  }

  Número de dias no week_structure: exatamente {{days_per_week}}.
  Grupos musculares válidos: #{VALID_GROUPS.join(', ')}.
  Métodos válidos: #{VALID_METHODS.join(', ')}.
PROMPT

AiPromptVersion.find_or_create_by(name: "workout_generation", version: "v1") do |pv|
  pv.prompt_type = "user"
  pv.content     = workout_prompt_v1
  pv.active      = true
  pv.metadata    = { created_by: "seeds", description: "Prompt v1 com contexto de fitness_profile e arquétipo" }
end

AiPromptVersion.where(name: "workout_generation").where.not(version: "v1").update_all(active: false)
puts "#{AiPromptVersion.count} AI prompt versions seeded"
