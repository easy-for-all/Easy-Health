class ExerciseIntelligenceService
  # ──────────────────────────────────────────────────────────────
  # Dictionaries
  # ──────────────────────────────────────────────────────────────

  ACTIVITY_ALIASES = {
    "bicicleta"        => "bike",
    "bike"             => "bike",
    "ciclismo"         => "bike",
    "spinning"         => "bike",
    "corrida"          => "running",
    "correr"           => "running",
    "run"              => "running",
    "running"          => "running",
    "caminhada"        => "walking",
    "andar"            => "walking",
    "walking"          => "walking",
    "musculacao"       => "strength_training",
    "musculação"       => "strength_training",
    "academia"         => "strength_training",
    "peso"             => "strength_training",
    "weights"          => "strength_training",
    "strength"         => "strength_training",
    "strength_training" => "strength_training",
    "funcional"        => "functional",
    "functional"       => "functional",
    "mobilidade"       => "mobility",
    "mobility"         => "mobility",
    "alongamento"      => "stretching",
    "stretching"       => "stretching",
    "cardio"           => "cardio",
    "hiit"             => "hiit",
    "natacao"          => "swimming",
    "natação"          => "swimming",
    "swimming"         => "swimming",
  }.freeze

  EQUIPMENT_ALIASES = {
    "corda"       => "rope",
    "rope"        => "rope",
    "cabo"        => "cable",
    "cable"       => "cable",
    "barra"       => "barbell",
    "barbell"     => "barbell",
    "halter"      => "dumbbell",
    "halteres"    => "dumbbell",
    "dumbbell"    => "dumbbell",
    "maquina"     => "machine",
    "máquina"     => "machine",
    "machine"     => "machine",
    "peso corporal" => "bodyweight",
    "bodyweight"  => "bodyweight",
    "sem peso"    => "bodyweight",
    "elastico"    => "band",
    "elástico"    => "band",
    "band"        => "band",
    "kettlebell"  => "kettlebell",
    "esteira"     => "cardio",
    "bike"        => "cardio",
  }.freeze

  MUSCLE_ALIASES = {
    "peito"     => "chest",
    "peitoral"  => "chest",
    "chest"     => "chest",
    "costas"    => "back",
    "dorsal"    => "back",
    "back"      => "back",
    "ombro"     => "shoulders",
    "ombros"    => "shoulders",
    "shoulder"  => "shoulders",
    "shoulders" => "shoulders",
    "biceps"    => "biceps",
    "bíceps"    => "biceps",
    "triceps"   => "triceps",
    "tríceps"   => "triceps",
    "perna"     => "legs",
    "pernas"    => "legs",
    "legs"      => "legs",
    "quadriceps" => "legs",
    "quadríceps" => "legs",
    "gluteos"   => "glutes",
    "glúteos"   => "glutes",
    "glutes"    => "glutes",
    "core"      => "core",
    "abdomen"   => "core",
    "abdômen"   => "core",
    "abdominal" => "core",
    "panturrilha" => "calves",
    "calves"    => "calves",
    "trapezio"  => "trapezius",
    "trapézio"  => "trapezius",
    "trapezius" => "trapezius",
    "antebraco" => "forearms",
    "antebraço" => "forearms",
    "forearms"  => "forearms",
  }.freeze

  # Intent type constants
  INTENT_REPLACE         = "replace_exercise"
  INTENT_CARDIO          = "replace_with_cardio"
  INTENT_SAME_MOVEMENT   = "same_movement_new_equipment"
  INTENT_NO_EQUIPMENT    = "equipment_unavailable"
  INTENT_HOME            = "home_exercise"
  INTENT_PAIN            = "pain_constraint"
  INTENT_LIGHTER         = "reduce_intensity"
  INTENT_HEAVIER         = "increase_intensity"
  INTENT_FAVORITE        = "use_favorite"
  INTENT_MORE_OPTIONS    = "request_more_options"
  INTENT_AMBIGUOUS       = "ambiguous"
  INTENT_GENERAL         = "general_swap"

  # ──────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────

  def self.normalize_text(text)
    return "" if text.blank?
    text.to_s.downcase
        .unicode_normalize(:nfd)
        .gsub(/\p{Mn}/, "")
        .gsub(/\s+/, " ")
        .strip
  end

  def self.resolve_activity(text)
    normalized = normalize_text(text)
    ACTIVITY_ALIASES[normalized] || ACTIVITY_ALIASES[text.to_s.strip.downcase]
  end

  def self.resolve_equipment(text)
    normalized = normalize_text(text)
    EQUIPMENT_ALIASES[normalized] || EQUIPMENT_ALIASES[text.to_s.strip.downcase]
  end

  def self.resolve_muscle(text)
    normalized = normalize_text(text)
    MUSCLE_ALIASES[normalized] || MUSCLE_ALIASES[text.to_s.strip.downcase]
  end

  def self.parse_user_intent(text)
    raw      = text.to_s
    norm     = normalize_text(raw)

    result = {
      raw_text:         raw,
      normalized_text:  norm,
      intent_type:      INTENT_GENERAL,
      target_activity:  nil,
      target_muscle:    nil,
      target_equipment: nil,
      avoid_equipment:  nil,
      location:         nil,
      intensity:        nil,
      constraint:       nil,
    }

    # Pain / constraint
    if norm.match?(/\b(dor|doendo|machucado|machucada|lesao|lesão|desconforto|inflamado)\b/)
      result[:intent_type] = INTENT_PAIN
      if norm.match?(/\b(ombro|ombros|shoulder)\b/)
        result[:constraint] = "shoulder_pain"
      elsif norm.match?(/\b(joelho|joelhos|knee)\b/)
        result[:constraint] = "knee_pain"
      elsif norm.match?(/\b(lombar|coluna|costas)\b/)
        result[:constraint] = "lower_back_pain"
      elsif norm.match?(/\b(punho|pulso|wrist)\b/)
        result[:constraint] = "wrist_pain"
      else
        result[:constraint] = "pain"
      end
      return result
    end

    # No equipment available
    if norm.match?(/\b(nao tenho|não tenho|sem|nao tem|não tem)\b.*\b(aparelho|equipamento|maquina|máquina|cabo|barra|halter|corda)\b/)
      result[:intent_type] = INTENT_NO_EQUIPMENT
      detected_equip = detect_equipment_in_text(norm)
      result[:avoid_equipment] = detected_equip || "current_equipment"
      return result
    end

    # Home exercise
    if norm.match?(/\b(em casa|casa|home|sem academia|sem equipamento|sem aparelho)\b/)
      result[:intent_type] = INTENT_HOME
      result[:location]    = "home"
    end

    # Lighter / easier
    if norm.match?(/\b(mais leve|mais facil|mais fácil|iniciante|basico|básico|menos intenso)\b/)
      result[:intent_type] = INTENT_LIGHTER
      result[:intensity]   = "lighter"
      return result
    end

    # Heavier / harder
    if norm.match?(/\b(mais pesado|mais difícil|mais dificil|avancado|avançado|mais intenso|progredir|progressao)\b/)
      result[:intent_type] = INTENT_HEAVIER
      result[:intensity]   = "heavier"
      return result
    end

    # Favorite
    if norm.match?(/\b(favorito|favoritos|que eu gosto|que eu curtei|curtido)\b/)
      result[:intent_type] = INTENT_FAVORITE
      return result
    end

    # More options — but only when no specific muscle/equipment is mentioned
    if norm.match?(/\b(outra opcao|outras opcoes|outra opção|outras opções|mais opcoes|mais opções|outra alternativa)\b/) ||
       (norm.match?(/\b(outro exercicio|diferente)\b/) && detect_muscle_in_text(norm).nil? && detect_equipment_in_text(norm).nil?)
      result[:intent_type] = INTENT_MORE_OPTIONS
      return result
    end

    # Cardio / activity swap
    cardio_activity = detect_cardio_activity(norm)
    if cardio_activity
      result[:intent_type]     = INTENT_CARDIO
      result[:target_activity] = cardio_activity
      return result
    end

    # Same movement with new equipment
    if norm.match?(/\b(mesmo movimento|mesma coisa|parecido|similar)\b.*\b(com|usando|na|no)\b/)
      detected_equip = detect_equipment_in_text(norm)
      if detected_equip
        result[:intent_type]      = INTENT_SAME_MOVEMENT
        result[:target_equipment] = detected_equip
        return result
      end
    end

    # Equipment specific request
    detected_equip = detect_equipment_in_text(norm)
    detected_muscle = detect_muscle_in_text(norm)

    if detected_equip || detected_muscle
      result[:intent_type]      = INTENT_REPLACE
      result[:target_equipment] = detected_equip
      result[:target_muscle]    = detected_muscle
      return result
    end

    # Home was detected earlier but no other intent matched
    return result if result[:intent_type] == INTENT_HOME

    # Could not parse locally — mark as ambiguous for OpenAI
    if raw.length > 15
      result[:intent_type] = INTENT_AMBIGUOUS
    end

    result
  end

  # Returns exercises ranked for the given context.
  # Returns array of { exercise:, score:, reason: }
  def self.rank_replacement_exercises(user:, current_exercise:, intent:, already_suggested_ids: [])
    favorites_ids  = user.user_favorite_exercises.pluck(:exercise_id)
    completed_ids  = completed_exercise_ids(user)
    limitations    = user.health_profile&.limitations || []

    candidates = build_candidate_scope(current_exercise, intent)
    candidates = candidates.where.not(id: already_suggested_ids) if already_suggested_ids.any?

    scored = candidates.map do |exercise|
      score_data = score_exercise(
        exercise:             exercise,
        current_exercise:     current_exercise,
        intent:               intent,
        already_suggested_ids: already_suggested_ids,
        favorites_ids:        favorites_ids,
        completed_ids:        completed_ids,
        limitations:          limitations,
      )

      {
        exercise: exercise,
        score:    score_data[:total],
        reason:   build_reason(exercise, score_data, intent, favorites_ids, completed_ids),
      }
    end

    scored.sort_by { |s| -s[:score] }
  end

  # ──────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────

  private_class_method def self.detect_cardio_activity(norm)
    return "bike"    if norm.match?(/\b(bike|bicicleta|ciclismo|spinning)\b/)
    return "running" if norm.match?(/\b(corrida|correr|run|running)\b/)
    return "walking" if norm.match?(/\b(caminhada|andar|walking)\b/)
    return "cardio"  if norm.match?(/\b(cardio|aerobico|aeróbico)\b/)
    return "hiit"    if norm.match?(/\b(hiit|tabata|circuito)\b/)
    nil
  end

  private_class_method def self.detect_equipment_in_text(norm)
    EQUIPMENT_ALIASES.each_key do |key|
      return EQUIPMENT_ALIASES[key] if norm.include?(key)
    end
    nil
  end

  private_class_method def self.detect_muscle_in_text(norm)
    MUSCLE_ALIASES.each_key do |key|
      return MUSCLE_ALIASES[key] if norm.include?(key)
    end
    nil
  end

  private_class_method def self.completed_exercise_ids(user)
    logs = user.workout_sessions.order(created_at: :desc).limit(30).pluck(:exercise_logs)
    ids  = Set.new
    logs.each do |log_array|
      next unless log_array.is_a?(Array)
      log_array.each { |l| ids.add(l["exercise_id"]) if l["exercise_id"] }
    end
    ids
  end

  private_class_method def self.build_candidate_scope(current_exercise, intent)
    base = Exercise.browseable

    case intent[:intent_type]
    when INTENT_CARDIO
      activity = intent[:target_activity]
      base = base.where(exercise_type: cardio_type_for(activity))
    when INTENT_HOME
      base = base.where(home_compatible: true)
    when INTENT_LIGHTER
      base = base.where.not(difficulty_level: "advanced")
                 .where(muscle_group: current_exercise.muscle_group)
    when INTENT_HEAVIER
      base = base.where.not(difficulty_level: "beginner")
                 .where(muscle_group: current_exercise.muscle_group)
    when INTENT_PAIN
      base = base.where(muscle_group: current_exercise.muscle_group)
    else
      if intent[:target_muscle].present?
        base = base.where(muscle_group: intent[:target_muscle])
      else
        base = base.where(muscle_group: current_exercise.muscle_group)
      end

      if intent[:target_equipment].present?
        equip = map_equipment_to_db(intent[:target_equipment])
        base = base.where(equipment_type: equip) if equip
      end
    end

    base.where.not(id: current_exercise.id)
  end

  private_class_method def self.cardio_type_for(activity)
    case activity
    when "bike"    then %w[cardio]
    when "running" then %w[corrida cardio]
    when "walking" then %w[caminhada cardio]
    when "hiit"    then %w[hiit cardio]
    else %w[cardio corrida caminhada hiit]
    end
  end

  private_class_method def self.map_equipment_to_db(canonical)
    mapping = {
      "rope"      => "cable",
      "cable"     => "cable",
      "barbell"   => "barbell",
      "dumbbell"  => "dumbbell",
      "machine"   => "machine",
      "bodyweight" => "bodyweight",
      "band"      => "bodyweight",
      "kettlebell" => "dumbbell",
      "cardio"    => "cardio",
    }
    mapping[canonical]
  end

  private_class_method def self.score_exercise(exercise:, current_exercise:, intent:, already_suggested_ids:, favorites_ids:, completed_ids:, limitations:)
    s = Hash.new(0)

    s[:same_muscle]   = 40 if exercise.muscle_group == current_exercise.muscle_group
    s[:equipment_req] = 30 if intent[:target_equipment].present? &&
                               map_equipment_to_db(intent[:target_equipment]) == exercise.equipment_type
    s[:favorite]      = 20 if favorites_ids.include?(exercise.id)
    s[:completed]     = 15 if completed_ids.include?(exercise.id)
    s[:has_gif]       = 10 if exercise.gif_url.present?

    s[:already_shown] = -50 if already_suggested_ids.include?(exercise.id)

    if intent[:constraint].present?
      constrained_muscles = constraint_to_muscles(intent[:constraint])
      s[:contraindicated] = -80 if constrained_muscles.include?(exercise.muscle_group)
    end

    if intent[:avoid_equipment].present? && intent[:avoid_equipment] != "current_equipment"
      avoid_db = map_equipment_to_db(intent[:avoid_equipment])
      s[:unavailable_equip] = -40 if avoid_db && exercise.equipment_type == avoid_db
    end

    if intent[:intensity] == "lighter"
      s[:difficulty_match] = 10 if %w[beginner intermediate].include?(exercise.difficulty_level)
      s[:difficulty_miss]  = -20 if exercise.difficulty_level == "advanced"
    elsif intent[:intensity] == "heavier"
      s[:difficulty_match] = 10 if %w[intermediate advanced].include?(exercise.difficulty_level)
      s[:difficulty_miss]  = -20 if exercise.difficulty_level == "beginner"
    end

    total = s.values.sum
    s[:total] = total
    s
  end

  private_class_method def self.constraint_to_muscles(constraint)
    {
      "shoulder_pain"    => %w[shoulders],
      "knee_pain"        => %w[legs],
      "lower_back_pain"  => %w[back core],
      "wrist_pain"       => %w[chest shoulders biceps triceps forearms],
      "pain"             => [],
    }.fetch(constraint, [])
  end

  private_class_method def self.build_reason(exercise, score_data, intent, favorites_ids, completed_ids)
    reasons = []

    reasons << "Você já favoritou esse exercício." if score_data[:favorite].to_i > 0
    reasons << "Você já realizou esse exercício antes." if score_data[:completed].to_i > 0

    case intent[:intent_type]
    when INTENT_CARDIO
      activity_label = intent[:target_activity]&.capitalize || "cardio"
      reasons << "Sugeri #{activity_label} porque você pediu uma opção de cardio."
    when INTENT_HOME
      reasons << "Compatível com treino em casa."
    when INTENT_LIGHTER
      reasons << "Opção mais leve que o exercício atual."
    when INTENT_HEAVIER
      reasons << "Opção mais intensa para progressão."
    when INTENT_PAIN
      reasons << "Evitei exercícios que sobrecarregam a região com desconforto."
    when INTENT_NO_EQUIPMENT
      reasons << "Alternativa sem o equipamento que você não tem disponível."
    when INTENT_SAME_MOVEMENT
      equip = intent[:target_equipment]&.capitalize
      reasons << "Mesmo padrão de movimento com #{equip || "outro equipamento"}."
    else
      reasons << "Mesmo grupo muscular do exercício atual." if score_data[:same_muscle].to_i > 0
      equip = intent[:target_equipment]
      reasons << "Usa #{equip} conforme solicitado." if equip.present? && score_data[:equipment_req].to_i > 0
    end

    reasons << "Tem demonstração em GIF." if score_data[:has_gif].to_i > 0 && reasons.empty?
    reasons << "Boa alternativa para #{exercise.muscle_group}." if reasons.empty?

    reasons.first(2).join(" ")
  end
end
