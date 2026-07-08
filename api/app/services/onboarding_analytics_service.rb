class OnboardingAnalyticsService
  DISPLAY_FLOWS = %w[quick complete photo_ai chat_ai].freeze

  FLOW_LABELS = {
    "quick" => "Rápido",
    "complete" => "Completo",
    "photo_ai" => "Foto IA",
    "chat_ai" => "Conversar com IA",
    "legacy" => "Dados antigos"
  }.freeze

  STEPS_BY_FLOW = {
    "quick" => %w[create-start quick-goal quick-profile quick-place quick-time quick-limits plan_created],
    "complete" => %w[create-start complete-goal complete-profile complete-method complete-place complete-focus complete-schedule complete-care plan_created],
    "photo_ai" => [],
    "chat_ai" => []
  }.freeze

  STEP_LABELS = {
    "create-start" => "Escolheu fluxo",
    "quick-goal" => "Objetivo",
    "quick-profile" => "Dados físicos",
    "quick-place" => "Local",
    "quick-time" => "Tempo",
    "quick-limits" => "Limitações",
    "complete-goal" => "Objetivo",
    "complete-profile" => "Nível/dados físicos",
    "complete-method" => "Método",
    "complete-place" => "Local/equipamentos",
    "complete-focus" => "Focos",
    "complete-schedule" => "Rotina",
    "complete-care" => "Preferências/cuidados",
    "plan_created" => "Criou treino"
  }.freeze

  QUESTION_LABELS = {
    "workout_difficulty_feedback" => "Como foi o treino",
    "available_equipment" => "Equipamento disponível",
    "avoid_exercise" => "Evitar exercício",
    "training_preference" => "Preferência de treino",
    "preferred_training_location" => "Onde treina",
    "activation_goal_focus" => "Resultado desejado"
  }.freeze

  GOAL_LABELS = {
    "lose_weight" => "Emagrecer", "gain_muscle" => "Ganhar massa", "maintain" => "Manter",
    "health" => "Saúde", "body_definition" => "Definir", "conditioning" => "Condicionamento",
    "strength" => "Força", "mobility" => "Mobilidade", "safe_return" => "Retorno com segurança",
    "health_longevity" => "Saúde/longevidade"
  }.freeze

  LOCATION_LABELS = {
    "full_gym" => "Academia completa", "simple_gym" => "Academia simples", "home" => "Casa",
    "condo" => "Condomínio", "outdoor" => "Ar livre", "hotel_travel" => "Hotel/viagem",
    "unknown" => "Ainda não sei"
  }.freeze

  INTENSITY_LABELS = {
    "easy_start" => "Fácil de começar", "balanced" => "Equilibrado", "intense" => "Mais intenso",
    "progressive" => "Progressivo", "unknown" => "Não informado"
  }.freeze

  STYLE_LABELS = {
    "short_sessions" => "Mais curto", "traditional_strength" => "Mais intenso",
    "cardio" => "Mais cardio", "functional" => "Funcional", "calisthenics" => "Mais musculação",
    "mobility" => "Mobilidade", "mixed" => "Misturado", "unknown" => "Não informado"
  }.freeze

  ACTIVATION_STEPS = %w[
    plan_created
    activation_ready_screen_viewed
    activation_preview_viewed
    activation_exercise_details_opened
    activation_start_clicked
    first_workout_started
    first_exercise_started
    first_exercise_completed
    first_workout_completed
  ].freeze

  ACTIVATION_STEP_LABELS = {
    "plan_created" => "Treino criado",
    "activation_ready_screen_viewed" => "Tela pronto visualizada",
    "activation_preview_viewed" => "Preview visualizado",
    "activation_exercise_details_opened" => "Detalhe de exercício aberto",
    "activation_start_clicked" => "Clicou iniciar",
    "first_workout_started" => "Primeiro treino iniciado",
    "first_exercise_started" => "Primeiro exercício iniciado",
    "first_exercise_completed" => "Primeiro exercício concluído",
    "first_workout_completed" => "Primeiro treino concluído"
  }.freeze

  LIMITATION_KEYWORDS = {
    "Joelho" => /joelho/i, "Lombar" => /lombar|coluna/i, "Ombro" => /ombro/i, "Punho" => /punho/i,
    "Pescoço" => /pesco/i, "Quadril" => /quadril/i, "Pós-parto" => /p[oó]s.?parto/i,
    "Retorno de lesão" => /les[aã]o/i
  }.freeze

  def initialize(period: nil, flow: nil, status: nil)
    @period = period
    @flow_filter = DISPLAY_FLOWS.include?(flow) ? flow : nil
    @status_filter = %w[trial_active trial_expired premium].include?(status) ? status : nil
  end

  def call
    {
      flow_selection: flow_selection,
      conversion_by_flow: conversion_by_flow,
      time_to_first_plan: time_to_first_plan,
      step_dropoff: step_dropoff,
      first_workout_24h: first_workout_24h,
      progressive_profiling: progressive_profiling,
      ai_quality: ai_quality,
      declared_preferences: declared_preferences,
      activation_funnel: activation_funnel
    }
  end

  private

  attr_reader :period, :flow_filter, :status_filter

  # ---- shared scopes ----

  def period_from
    case period
    when "today" then Time.current.beginning_of_day
    when "7d" then 7.days.ago
    when "30d" then 30.days.ago
    else nil
    end
  end

  def events_scope
    scope = OnboardingEvent.all
    scope = scope.where(occurred_at: period_from..) if period_from
    scope
  end

  def flows_to_display
    flow_filter ? [flow_filter] : DISPLAY_FLOWS
  end

  def users_scope
    scope = User.left_joins(:subscription)
    case status_filter
    when "trial_active"
      scope = scope.where("users.trial_ends_at > ?", Time.current)
                   .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
    when "trial_expired"
      scope = scope.where("users.trial_ends_at <= ?", Time.current)
                   .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
    when "premium"
      scope = scope.where(subscriptions: { status: "active" })
    end
    scope
  end

  def filtered_user_ids
    @filtered_user_ids ||= users_scope.pluck(:id)
  end

  # ---- Visão 1: escolha do fluxo ----

  def flow_selection
    counts = events_scope.named("onboarding_flow_selected")
                          .where(user_id: filtered_user_ids)
                          .group(:onboarding_flow).distinct.count(:user_id)
    total = counts.values.sum

    {
      total: total,
      by_flow: flows_to_display.index_with do |flow|
        count = counts[flow].to_i
        { label: FLOW_LABELS[flow], count: count, pct: pct(count, total) }
      end
    }
  end

  # ---- Visão 2: conversão por fluxo ----

  def conversion_by_flow
    flows_to_display.index_with { |flow| conversion_row(flow) }
  end

  def conversion_row(flow)
    user_ids = User.where(onboarding_flow: flow, id: filtered_user_ids).pluck(:id)
    selected = user_ids.size
    return empty_conversion_row(flow) if selected.zero?

    created_workout = WorkoutPlan.where(user_id: user_ids).distinct.count(:user_id)
    executed_first = WorkoutSession.where(user_id: user_ids, completion_status: "completed").distinct.count(:user_id)
    plus2 = WorkoutSession.where(user_id: user_ids, completion_status: "completed").group(:user_id).having("COUNT(*) >= 2").count.size
    plus3 = WorkoutSession.where(user_id: user_ids, completion_status: "completed").group(:user_id).having("COUNT(*) >= 3").count.size
    subscribed = User.joins(:subscription).where(id: user_ids, subscriptions: { status: "active" }).count

    {
      label: FLOW_LABELS[flow],
      selected: selected,
      created_workout: created_workout,
      executed_first: executed_first,
      plus2_sessions: plus2,
      plus3_sessions: plus3,
      subscribed: subscribed,
      conversion_to_workout_pct: pct(created_workout, selected),
      conversion_to_subscription_pct: pct(subscribed, selected)
    }
  end

  def empty_conversion_row(flow)
    {
      label: FLOW_LABELS[flow], selected: 0, created_workout: 0, executed_first: 0,
      plus2_sessions: 0, plus3_sessions: 0, subscribed: 0,
      conversion_to_workout_pct: 0, conversion_to_subscription_pct: 0
    }
  end

  # ---- Visão 3: tempo até criar treino ----

  def time_to_first_plan
    selected_at_by_user = events_scope.named("onboarding_flow_selected").group(:user_id).minimum(:occurred_at)
    created_at_by_user = events_scope.named("plan_created").group(:user_id).minimum(:occurred_at)
    flow_by_user = events_scope.named("onboarding_flow_selected").pluck(:user_id, :onboarding_flow).to_h

    durations = Hash.new { |h, k| h[k] = [] }
    selected_at_by_user.each do |user_id, selected_at|
      created_at = created_at_by_user[user_id]
      flow = flow_by_user[user_id]
      next unless created_at && flow && DISPLAY_FLOWS.include?(flow)
      next if flow_filter && flow != flow_filter

      durations[flow] << (created_at - selected_at)
    end

    flows_to_display.index_with { |flow| duration_stats(durations[flow], flow) }
  end

  def duration_stats(seconds_list, flow)
    return { label: FLOW_LABELS[flow], count: 0 } if seconds_list.blank?

    sorted = seconds_list.sort
    {
      label: FLOW_LABELS[flow],
      count: sorted.size,
      avg_seconds: (sorted.sum / sorted.size).round,
      median_seconds: percentile(sorted, 50).round,
      p75_seconds: percentile(sorted, 75).round,
      avg_label: duration_label(sorted.sum / sorted.size),
      median_label: duration_label(percentile(sorted, 50))
    }
  end

  def percentile(sorted, pct)
    return 0.0 if sorted.empty?
    idx = ((pct / 100.0) * (sorted.size - 1)).round
    sorted[idx].to_f
  end

  def duration_label(seconds)
    seconds = seconds.to_f
    return "#{seconds.round}s" if seconds < 60
    minutes = (seconds / 60).floor
    remaining = (seconds % 60).round
    "#{minutes}m#{remaining.to_s.rjust(2, '0')}s"
  end

  # ---- Visão 4: abandono por etapa ----

  def step_dropoff
    flows_to_display.index_with { |flow| funnel_for_flow(flow) }
  end

  def funnel_for_flow(flow)
    steps = STEPS_BY_FLOW[flow]
    return [] if steps.blank?

    viewed_counts = events_scope.named("onboarding_step_viewed").for_flow(flow).group(:step_name).distinct.count(:user_id)
    completed_counts = events_scope.named("onboarding_step_completed").for_flow(flow).group(:step_name).distinct.count(:user_id)
    plan_created_users = events_scope.named("plan_created").for_flow(flow).distinct.count(:user_id)

    first_step_arrived = viewed_counts[steps.first].to_i

    steps.map do |step|
      arrived = step == "plan_created" ? completed_counts[steps[-2]].to_i : viewed_counts[step].to_i
      completed = step == "plan_created" ? plan_created_users : completed_counts[step].to_i

      {
        step_name: step,
        label: STEP_LABELS[step],
        arrived: arrived,
        completed: completed,
        dropoff_pct: arrived.positive? ? pct(arrived - completed, arrived) : 0,
        cumulative_pct: first_step_arrived.positive? ? pct(completed, first_step_arrived) : 0
      }
    end
  end

  # ---- Visão 5: ativação em 24h ----

  def first_workout_24h
    signup_base = User.where(id: filtered_user_ids)
    signup_base = signup_base.where(created_at: period_from..) if period_from
    total_signups = signup_base.count

    activated_24h_user_ids = events_scope.named("first_workout_completed_24h").where(user_id: filtered_user_ids).distinct.pluck(:user_id)
    plan_created_user_ids = events_scope.named("plan_created").where(user_id: filtered_user_ids).distinct.pluck(:user_id)
    activated_from_plan = (activated_24h_user_ids & plan_created_user_ids).size

    first_workout_times = events_scope.named("workout_completed")
                                       .where(user_id: filtered_user_ids, metadata: { is_first_workout: true })
                                       .joins(:user)
                                       .pluck("onboarding_events.occurred_at", "users.created_at")
    durations = first_workout_times.map { |completed_at, created_at| completed_at - created_at }.select { |d| d && d >= 0 }

    {
      overall: {
        signup_to_first_workout_24h: activated_24h_user_ids.size,
        signup_to_first_workout_24h_pct: pct(activated_24h_user_ids.size, total_signups),
        plan_to_first_workout_24h: activated_from_plan,
        plan_to_first_workout_24h_pct: pct(activated_from_plan, plan_created_user_ids.size),
        avg_time_label: durations.present? ? duration_label(durations.sum / durations.size) : nil,
        median_time_label: durations.present? ? duration_label(percentile(durations.sort, 50)) : nil
      },
      by_flow: flows_to_display.index_with { |flow| activation_row(flow) }
    }
  end

  def activation_row(flow)
    flow_user_ids = User.where(onboarding_flow: flow, id: filtered_user_ids).pluck(:id)
    return { label: FLOW_LABELS[flow], activated_24h: 0, activated_24h_pct: 0 } if flow_user_ids.empty?

    activated = events_scope.named("first_workout_completed_24h").where(user_id: flow_user_ids).distinct.count(:user_id)
    { label: FLOW_LABELS[flow], activated_24h: activated, activated_24h_pct: pct(activated, flow_user_ids.size) }
  end

  # ---- Visão 6: progressive profiling ----

  def progressive_profiling
    shown = events_scope.named("progressive_question_shown").where(user_id: filtered_user_ids).group(:step_name).count
    answered = events_scope.named("progressive_question_answered").where(user_id: filtered_user_ids).group(:step_name).count
    skipped = events_scope.named("progressive_question_skipped").where(user_id: filtered_user_ids).group(:step_name).count

    total_shown = shown.values.sum
    total_answered = answered.values.sum
    total_skipped = skipped.values.sum

    by_question = QUESTION_LABELS.keys.map do |key|
      q_shown = shown[key].to_i
      q_answered = answered[key].to_i
      q_skipped = skipped[key].to_i
      top_answer = top_answer_for(key)

      {
        question_key: key,
        label: QUESTION_LABELS[key],
        shown: q_shown,
        answered: q_answered,
        skipped: q_skipped,
        answer_rate_pct: pct(q_answered, q_shown),
        top_answer: top_answer
      }
    end

    {
      summary: {
        shown: total_shown,
        answered: total_answered,
        skipped: total_skipped,
        answer_rate_pct: pct(total_answered, total_shown),
        skip_rate_pct: pct(total_skipped, total_shown)
      },
      by_question: by_question
    }
  end

  def top_answer_for(question_key)
    answers = events_scope.named("progressive_question_answered")
                           .where(user_id: filtered_user_ids, step_name: question_key)
                           .pluck(:metadata)
                           .filter_map { |m| m["answer_value"] }
    return nil if answers.blank?

    answers.tally.max_by { |_, count| count }&.first
  end

  # ---- Visão 7: qualidade dos fluxos IA ----

  def ai_quality
    %w[photo_ai chat_ai].index_with { |flow| ai_quality_row(flow) }
  end

  def ai_quality_row(flow)
    generated = events_scope.named("ai_summary_generated").for_flow(flow).where(user_id: filtered_user_ids).count
    edited = events_scope.named("ai_summary_edited").for_flow(flow).where(user_id: filtered_user_ids).count
    accepted = events_scope.named("ai_plan_accepted").for_flow(flow).where(user_id: filtered_user_ids).count
    regenerated = events_scope.named("ai_plan_regenerated").for_flow(flow).where(user_id: filtered_user_ids).count
    abandoned = events_scope.named("ai_plan_abandoned").for_flow(flow).where(user_id: filtered_user_ids).count

    {
      label: FLOW_LABELS[flow],
      summaries_generated: generated,
      summaries_edited: edited,
      plans_accepted: accepted,
      plans_regenerated: regenerated,
      plans_abandoned: abandoned,
      acceptance_pct: pct(accepted, generated),
      edit_pct: pct(edited, generated),
      regeneration_pct: pct(regenerated, generated),
      abandonment_pct: pct(abandoned, generated)
    }
  end

  # ---- Visão 8: preferências declaradas ----

  def declared_preferences
    profiles = HealthProfile.where(user_id: filtered_user_ids)
    total = profiles.count
    return empty_preferences if total.zero?

    {
      goals: distribution(profiles.group(:goal).count, GOAL_LABELS, total),
      locations: distribution(profiles.group(:training_location).count, LOCATION_LABELS, total),
      durations: distribution(bucket_durations(profiles.pluck(:session_duration_minutes)), nil, total),
      frequencies: distribution(bucket_frequencies(profiles.pluck(:training_days_per_week)), nil, total),
      limitations: distribution(bucket_limitations(profiles.pluck(:limitations)), nil, total),
      training_preference: {
        intensity: distribution(profiles.group(:intensity_preference).count, INTENSITY_LABELS, total),
        style: distribution(bucket_array_column(profiles.pluck(:preferred_training_styles)), STYLE_LABELS, total)
      }
    }
  end

  def empty_preferences
    { goals: [], locations: [], durations: [], frequencies: [], limitations: [], training_preference: { intensity: [], style: [] } }
  end

  def distribution(counts, labels, total)
    counts.compact.reject { |k, _| k.nil? || k == "" }
          .sort_by { |_, count| -count }
          .map do |key, count|
            {
              key: key,
              label: labels ? (labels[key] || key.to_s) : key.to_s,
              count: count,
              pct: pct(count, total)
            }
          end
  end

  def bucket_durations(values)
    values.compact.each_with_object(Hash.new(0)) do |minutes, acc|
      label = minutes.to_i >= 60 ? "60+" : minutes.to_s
      acc[label] += 1
    end
  end

  def bucket_frequencies(values)
    values.compact.each_with_object(Hash.new(0)) do |days, acc|
      label = days.to_i >= 6 ? "6x+" : "#{days}x"
      acc[label] += 1
    end
  end

  def bucket_array_column(arrays)
    arrays.compact.flatten.each_with_object(Hash.new(0)) { |value, acc| acc[value] += 1 }
  end

  def bucket_limitations(arrays)
    arrays.compact.each_with_object(Hash.new(0)) do |limitations, acc|
      if limitations.blank?
        acc["Nenhuma"] += 1
        next
      end

      matched = false
      limitations.each do |text|
        LIMITATION_KEYWORDS.each do |label, pattern|
          next unless text.to_s.match?(pattern)
          acc[label] += 1
          matched = true
        end
      end
      acc["Outro"] += 1 unless matched
    end
  end

  # ---- Visão 9: funil de ativação (treino criado -> primeiro treino concluído) ----

  def activation_funnel
    {
      steps: activation_funnel_steps(filtered_user_ids),
      by_flow: flows_to_display.index_with do |flow|
        flow_user_ids = User.where(onboarding_flow: flow, id: filtered_user_ids).pluck(:id)
        { label: FLOW_LABELS[flow], steps: activation_funnel_steps(flow_user_ids) }
      end
    }
  end

  def activation_funnel_steps(user_ids)
    counts = ACTIVATION_STEPS.map { |step| activation_step_count(step, user_ids) }
    first_count = counts.first.to_i

    ACTIVATION_STEPS.each_with_index.map do |step, idx|
      count = counts[idx]
      previous_count = idx.zero? ? count : counts[idx - 1]

      {
        step_name: step,
        label: ACTIVATION_STEP_LABELS[step],
        count: count,
        pct_of_previous: idx.zero? ? 100.0 : pct(count, previous_count),
        pct_of_start: pct(count, first_count)
      }
    end
  end

  def activation_step_count(step, user_ids)
    return 0 if user_ids.blank?

    case step
    when "first_workout_started"
      events_scope.named("workout_started").where(user_id: user_ids, metadata: { is_first_workout: true }).distinct.count(:user_id)
    when "first_workout_completed"
      events_scope.named("workout_completed").where(user_id: user_ids, metadata: { is_first_workout: true }).distinct.count(:user_id)
    else
      events_scope.named(step).where(user_id: user_ids).distinct.count(:user_id)
    end
  end

  # ---- helpers ----

  def pct(numerator, denominator)
    return 0 if denominator.to_i.zero?
    ((numerator.to_f / denominator) * 100).round(1)
  end
end
