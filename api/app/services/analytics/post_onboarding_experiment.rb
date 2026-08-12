module Analytics
  # EXPERIMENTO ANDROID — CONTA APÓS O ONBOARDING (android_post_onboarding_gate_v1)
  #
  # Compara duas experiências no fim do onboarding pré-auth:
  #   account_gate  fluxo atual: resumo → /sign-up → conta → plano
  #   open_app      abre o app e gera o plano sem conta (modo anônimo)
  #
  # A UNIDADE É UMA INSTALAÇÃO EXPOSTA, NUNCA UM EVENTO. Mesma construção do
  # AndroidFunnel: GROUP BY properties->>'installation_id', de modo que uma
  # instalação que emitiu workout_started sete vezes conta uma.
  #
  # O DENOMINADOR É EXPOSIÇÃO, NÃO ATRIBUIÇÃO. Atribuídas incluem quem nunca
  # chegou à bifurcação; dividir por elas diluiria as duas variantes igualmente
  # e faria o experimento parecer menos eficaz do que é (ou mais).
  #
  # A JANELA DE 24h É RELATIVA AO exposed_at DAQUELA INSTALAÇÃO, não a um corte
  # global. Alguém exposto ontem às 23h e outro hoje às 8h têm janelas
  # diferentes; um corte único mediria durações diferentes como se fossem a mesma.
  #
  # Read-only por construção: todo método é um SELECT.
  class PostOnboardingExperiment
    EXPERIMENT_KEY = ExperimentRegistry::ANDROID_POST_ONBOARDING_GATE
    VARIANTS = ExperimentRegistry::EXPERIMENTS.fetch(EXPERIMENT_KEY).freeze

    VARIANT_LABELS = {
      "account_gate" => "Conta antes do plano",
      "open_app" => "Abre o app"
    }.freeze

    PLATFORM = "android".freeze

    EXPOSED_EVENT = "experiment_exposed".freeze
    ASSIGNED_EVENT = "experiment_assigned".freeze

    PERIODS = %w[since_start today 7d 30d].freeze
    DEFAULT_PERIOD = "since_start".freeze

    AUDIENCES = AndroidFunnel::AUDIENCES
    DEFAULT_AUDIENCE = AndroidFunnel::DEFAULT_AUDIENCE

    VARIANT_FILTERS = (%w[all] + VARIANTS).freeze
    DEFAULT_VARIANT_FILTER = "all".freeze

    # O corte do experimento é SEPARADO do corte do funil: os dois podem estar em
    # builds diferentes, e reusar ANDROID_FUNNEL_MIN_BUILD faria uma mudança no
    # funil mexer silenciosamente na população do experimento.
    DEFAULT_MIN_BUILD = 0

    WINDOW_HOURS = 24

    # Métricas primárias e secundárias. Cada uma vira três leituras: mesmo dia,
    # 24h e acumulado.
    METRICS = [
      { key: "plan_generated",   label: "Plano gerado",        events: %w[workout_created] },
      { key: "workout_viewed",   label: "1º treino visualizado", events: %w[workout_viewed] },
      { key: "workout_started",  label: "1º treino iniciado",  events: %w[workout_first_exercise_started workout_started] },
      { key: "workout_completed", label: "1º treino concluído", events: %w[workout_completed] },
      { key: "account_created",  label: "Conta criada",        events: %w[signup_completed] }
    ].freeze

    # Caminhos DIFERENTES de propósito. Forçar as duas variantes num funil
    # sequencial único inventaria etapas que uma delas nunca atravessa — em
    # account_gate a conta vem antes do plano, em open_app vem depois (ou nunca).
    FUNNELS = {
      "account_gate" => [
        { key: "exposed",           label: "Exposta",              events: [] },
        { key: "gate_viewed",       label: "Viu a tela de conta",  events: %w[auth_screen_viewed] },
        { key: "auth_clicked",      label: "Escolheu um método",   events: %w[auth_provider_clicked] },
        { key: "auth_started",      label: "Auth iniciada",        events: %w[social_login_started signup_started login_started] },
        { key: "auth_completed",    label: "Auth concluída",       events: %w[signup_completed login_completed] },
        { key: "plan_opened",       label: "Plano aberto",         events: %w[workout_created workout_viewed] },
        { key: "workout_started",   label: "Treino iniciado",      events: %w[workout_first_exercise_started workout_started] },
        { key: "workout_completed", label: "Treino concluído",     events: %w[workout_completed] }
      ].freeze,
      "open_app" => [
        { key: "exposed",           label: "Exposta",              events: [] },
        { key: "plan_opened",       label: "Plano aberto",         events: %w[workout_created] },
        { key: "workout_viewed",    label: "Treino visualizado",   events: %w[workout_viewed] },
        { key: "workout_started",   label: "Treino iniciado",      events: %w[workout_first_exercise_started workout_started] },
        { key: "workout_completed", label: "Treino concluído",     events: %w[workout_completed] },
        { key: "limit_reached",     label: "Bateu o limite",       events: %w[anonymous_plan_limit_reached] },
        { key: "gate_seen_later",   label: "Viu a conta depois",   events: %w[auth_screen_viewed] },
        { key: "auth_completed",    label: "Auth concluída",       events: %w[signup_completed login_completed] }
      ].freeze
    }.freeze

    # Todo evento consultado, numa lista só — a query central é uma.
    OBSERVED_EVENTS = (
      METRICS.flat_map { |m| m[:events] } +
      FUNNELS.values.flat_map { |stages| stages.flat_map { |s| s[:events] } } +
      %w[auth_client_error auth_api_error login_failed social_login_failed anonymous_workouts_claim_failed]
    ).uniq.freeze

    ERROR_EVENTS = %w[auth_client_error auth_api_error login_failed social_login_failed].freeze

    # Avisos de amostra. Descritivos e nada mais: o painel nunca declara vencedor,
    # porque decidir exige horizonte fixo e métrica pré-registrada — coisas que
    # um painel não tem como saber que foram respeitadas.
    SAMPLE_FLOOR_DIRECTIONAL = 30
    SAMPLE_FLOOR_STABLE = 100

    READOUT_NOTE =
      "Leitura observacional. O painel não declara vencedor: para decidir é preciso " \
      "horizonte definido antes do início e uma métrica primária pré-registrada.".freeze

    UNIT_NOTE =
      "A unidade é installation_id distinto exposto. Eventos repetidos não somam, e " \
      "o denominador de toda taxa é a instalação EXPOSTA — nunca a atribuída.".freeze

    WINDOW_NOTE =
      "A janela de 24h é contada a partir do exposed_at de CADA instalação, não de um " \
      "corte global do período.".freeze

    STEP_DEFINITION = "post_onboarding_ab_step_v1".freeze

    class << self
      def min_build
        raw = ENV["ANDROID_POST_ONBOARDING_AB_MIN_BUILD"].to_s.strip
        raw.match?(/\A\d+\z/) ? Integer(raw) : DEFAULT_MIN_BUILD
      end

      # Início declarado do experimento. Sem ele o painel não tem como dizer que
      # uma instalação anterior ao deploy simplesmente não podia participar.
      def started_at
        raw = ENV["ANDROID_POST_ONBOARDING_AB_STARTED_AT"].to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end
    end

    def initialize(period: nil, build: nil, audience: nil, variant: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULT_PERIOD
      @audience = AUDIENCES.include?(audience.to_s) ? audience.to_s : DEFAULT_AUDIENCE
      @variant_filter = VARIANT_FILTERS.include?(variant.to_s) ? variant.to_s : DEFAULT_VARIANT_FILTER
      @build = build.to_s.strip.match?(/\A\d{1,9}\z/) ? Integer(build.to_s.strip) : nil
    end

    attr_reader :period, :audience, :build, :variant_filter

    def call
      {
        source: "product_analytics_events + app_installations + anonymous_onboarding_sessions",
        generated_at: ReportingTime.now.iso8601,
        experiment_key: EXPERIMENT_KEY,
        filters: { period: period, build: build, audience: audience, variant: variant_filter },
        definitions: definitions,
        header: header,
        metrics: metrics,
        funnels: funnels,
        last_stage: last_stage,
        guardrails: guardrails
      }
    end

    private

    # ------------------------------------------------------------------ escopo

    # Lido em tempo de chamada (o class method), nunca congelado no boot: o corte
    # pode mudar no servidor sem deploy, como o do funil.
    def min_build = @min_build ||= self.class.min_build

    def window
      return @window if defined?(@window)

      now = ReportingTime.now
      @window =
        case period
        when "today" then now.beginning_of_day..now
        when "7d" then (now.beginning_of_day - 6.days)..now
        when "30d" then (now.beginning_of_day - 29.days)..now
        end
    end

    def numeric_build = "(#{AppInstallation::NUMERIC_BUILD_SQL})"

    # Instalações Android elegíveis: plataforma e build, nada mais.
    #
    # O início do experimento NÃO entra aqui. Ele corta pelo momento do EVENTO
    # (started_clause), porque é assim que o cliente decide participação:
    # `Date.now() >= started_at`. Cortar por created_at excluiria do painel
    # instalações que o app tratou de verdade — e o app Android é WebView de site
    # remoto, então toda instalação já existente recebe o código novo assim que a
    # web sobe.
    def eligible_scope
      scope = AppInstallation.for_platform(PLATFORM)
      scope = scope.where("#{numeric_build} >= ?", min_build) if min_build.positive?
      scope = scope.where("#{numeric_build} = ?", build) if build
      scope
    end

    # Mesma classificação por IDENTIDADE do AndroidFunnel — nunca por fabricante.
    def cohort_scope
      @cohort_scope ||=
        case audience
        when "internal_test" then eligible_scope.where(id: non_external_scope.select(:id))
        when "all" then eligible_scope
        else eligible_scope.where.not(id: non_external_scope.select(:id))
        end
    end

    def non_external_scope
      scope = eligible_scope.where(user_id: non_external_user_ids)
      ids = automated_test_evidence_ids
      return scope if ids.empty?

      scope.or(eligible_scope.where(installation_id: ids))
    end

    def non_external_user_ids
      @non_external_user_ids ||=
        AccountClassification.internal_scope(User.all).pluck(:id) |
        AccountClassification.automated_test_scope(User.all).pluck(:id)
    end

    def automated_test_evidence_ids
      @automated_test_evidence_ids ||=
        ProductAnalyticsEvent
          .where(user_id: AccountClassification.automated_test_scope(User.all).select(:id))
          .where("product_analytics_events.properties->>'installation_id' IS NOT NULL")
          .distinct
          .pluck(Arel.sql("product_analytics_events.properties->>'installation_id'"))
          .compact
    end

    # ----------------------------------------------------------- exposições

    # Uma linha por instalação exposta: variante e exposed_at. É a espinha do
    # painel inteiro — tudo depois disto é medido contra esta lista.
    #
    # MIN(occurred_at) e não MAX: a exposição é o momento em que a variante
    # passou a valer, e uma segunda emissão (reinstalação, evento duplicado) não
    # pode empurrar a janela de 24h para frente.
    def exposures
      @exposures ||= begin
        sql = <<~SQL.squish
          SELECT e.properties->>'installation_id' AS installation_id,
                 MIN(e.occurred_at) AS exposed_at,
                 (ARRAY_AGG(e.properties->>'variant' ORDER BY e.occurred_at ASC))[1] AS variant,
                 COUNT(DISTINCT e.properties->>'variant') AS variant_count
          FROM product_analytics_events e
          WHERE e.event_name = #{quote(EXPOSED_EVENT)}
            AND e.properties->>'experiment_key' = #{quote(EXPERIMENT_KEY)}
            AND e.properties->>'installation_id' IN (#{cohort_scope.select(:installation_id).to_sql})
            #{started_clause("e.occurred_at")}
            #{window_clause("e.occurred_at")}
          GROUP BY 1
        SQL

        rows = ApplicationRecord.connection.select_all(sql).to_a
        rows.each_with_object({}) do |row, acc|
          variant = row["variant"]
          next unless VARIANTS.include?(variant)

          acc[row["installation_id"]] = {
            installation_id: row["installation_id"],
            variant: variant,
            exposed_at: parse_time(row["exposed_at"]),
            variant_count: row["variant_count"].to_i
          }
        end
      end
    end

    def filtered_exposures
      @filtered_exposures ||=
        if variant_filter == "all"
          exposures
        else
          exposures.select { |_id, row| row[:variant] == variant_filter }
        end
    end

    def exposures_by_variant
      @exposures_by_variant ||= filtered_exposures.values.group_by { |row| row[:variant] }
    end

    def exposed_count(variant) = exposures_by_variant.fetch(variant, []).size

    # ------------------------------------------------- eventos observados

    # Para cada instalação exposta, o primeiro occurred_at de cada evento
    # observado A PARTIR DA EXPOSIÇÃO DAQUELA INSTALAÇÃO.
    #
    # O piso é por instalação, e agregar sem ele quebra: um workout_created de
    # semanas atrás viraria o MIN, seria descartado por ser anterior à exposição,
    # e o workout_created POSTERIOR nunca apareceria — a instalação contaria como
    # "nunca gerou plano" tendo gerado. Isso não é hipotético desde que o corte de
    # início passou a admitir instalações pré-existentes, e o viés não é simétrico
    # entre os braços.
    #
    # Expressar esse piso em SQL exigiria um VALUES com os pares
    # (installation_id, exposed_at), join e cast. Não vale: filtered_exposures já
    # está em memória, então a query fica trivial e a dobra acontece aqui.
    def first_event_at
      @first_event_at ||= begin
        ids = filtered_exposures.keys
        return {} if ids.empty?

        sql = <<~SQL.squish
          SELECT e.properties->>'installation_id' AS installation_id,
                 e.event_name AS event_name,
                 e.occurred_at AS occurred_at
          FROM product_analytics_events e
          WHERE e.event_name IN (#{OBSERVED_EVENTS.map { |n| quote(n) }.join(', ')})
            AND e.properties->>'installation_id' IN (#{ids.map { |id| quote(id) }.join(', ')})
        SQL

        ApplicationRecord.connection.select_all(sql).to_a.each_with_object({}) do |row, acc|
          id = row["installation_id"]
          at = parse_time(row["occurred_at"])
          exposed_at = filtered_exposures.dig(id, :exposed_at)
          next if at.nil? || exposed_at.nil? || at < exposed_at

          acc[id] ||= {}
          current = acc[id][row["event_name"]]
          acc[id][row["event_name"]] = at if current.nil? || at < current
        end
      end
    end

    # A pergunta central: esta instalação emitiu algum destes eventos, dentro da
    # janela, DEPOIS da própria exposição?
    #
    # `after` importa: um treino iniciado ANTES da exposição não foi causado por
    # ela, e contá-lo atribuiria à variante algo que já tinha acontecido.
    def reached?(row, event_names, scope: :cumulative)
      events = first_event_at[row[:installation_id]] || {}
      exposed_at = row[:exposed_at]

      event_names.any? do |name|
        at = events[name]
        next false if at.nil? || exposed_at.nil? || at < exposed_at

        case scope
        when :within_24h then at <= exposed_at + WINDOW_HOURS.hours
        when :same_day then local_date(at) == local_date(exposed_at)
        else true
        end
      end
    end

    def count_reached(variant, event_names, scope:)
      exposures_by_variant.fetch(variant, []).count { |row| reached?(row, event_names, scope: scope) }
    end

    # ------------------------------------------------------------- cabeçalho

    def header
      assigned = assigned_counts

      {
        status: self.class.started_at.present? || min_build.positive? ? "ativo" : "não configurado",
        experiment_key: EXPERIMENT_KEY,
        min_build: min_build,
        started_at: self.class.started_at&.iso8601,
        expected_split: "50/50",
        assigned_installations: assigned.values.sum,
        exposed_installations: filtered_exposures.size,
        distribution: VARIANTS.map do |variant|
          {
            variant: variant,
            label: VARIANT_LABELS[variant],
            exposed: exposed_count(variant),
            share: ratio(exposed_count(variant), filtered_exposures.size, "post_onboarding_ab_share_v1"),
            sample_warning: sample_warning(exposed_count(variant))
          }
        end,
        # Atribuída e nunca exposta = instalação que recebeu variante e não
        # chegou ao fim do onboarding. Alto aqui não é bug do experimento, é
        # abandono do wizard — mas precisa ser visível para não ser confundido
        # com falha de instrumentação.
        assigned_without_exposure: ratio(
          [ assigned.values.sum - filtered_exposures.size, 0 ].max,
          assigned.values.sum,
          "post_onboarding_ab_unexposed_v1"
        )
      }
    end

    def assigned_counts
      @assigned_counts ||= begin
        sql = <<~SQL.squish
          SELECT e.properties->>'variant' AS variant,
                 COUNT(DISTINCT e.properties->>'installation_id') AS total
          FROM product_analytics_events e
          WHERE e.event_name = #{quote(ASSIGNED_EVENT)}
            AND e.properties->>'experiment_key' = #{quote(EXPERIMENT_KEY)}
            AND e.properties->>'installation_id' IN (#{cohort_scope.select(:installation_id).to_sql})
            #{started_clause("e.occurred_at")}
            #{window_clause("e.occurred_at")}
          GROUP BY 1
        SQL

        ApplicationRecord.connection.select_all(sql).to_a.each_with_object({}) do |row, acc|
          acc[row["variant"]] = row["total"].to_i if VARIANTS.include?(row["variant"])
        end
      end
    end

    # --------------------------------------------------------------- métricas

    def metrics
      rows = METRICS.map { |metric| metric_row(metric) }
      rows << d1_return_row
      rows << time_to_first_workout_row
      rows
    end

    def metric_row(metric)
      per_variant = VARIANTS.to_h do |variant|
        [
          variant,
          {
            same_day: ratio(count_reached(variant, metric[:events], scope: :same_day), exposed_count(variant), definition_for(metric[:key])),
            within_24h: ratio(count_reached(variant, metric[:events], scope: :within_24h), exposed_count(variant), definition_for(metric[:key])),
            cumulative: ratio(count_reached(variant, metric[:events], scope: :cumulative), exposed_count(variant), definition_for(metric[:key]))
          }
        ]
      end

      {
        key: metric[:key],
        label: metric[:label],
        unit: "installations",
        variants: per_variant,
        difference: difference_for(per_variant)
      }
    end

    # Diferença absoluta em pontos percentuais e relativa. Quando o denominador
    # da referência é zero, as duas ficam nil — o painel mostra "—", nunca
    # infinito e nunca 0%.
    def difference_for(per_variant)
      %i[same_day within_24h cumulative].to_h do |scope|
        control = per_variant.dig("account_gate", scope)
        treatment = per_variant.dig("open_app", scope)

        [ scope, difference_between(control, treatment) ]
      end
    end

    def difference_between(control, treatment)
      return { absolute_pp: nil, relative: nil } if control.nil? || treatment.nil?
      return { absolute_pp: nil, relative: nil } if control[:denominator].to_i.zero? || treatment[:denominator].to_i.zero?

      control_value = control[:value].to_f
      treatment_value = treatment[:value].to_f
      absolute = (treatment_value - control_value).round(1)

      {
        absolute_pp: absolute,
        # Divisão por zero não vira infinito: uma taxa de controle zerada não
        # torna o tratamento infinitamente melhor, torna a comparação impossível.
        relative: control_value.zero? ? nil : ((treatment_value - control_value) / control_value * 100).round(1)
      }
    end

    # Retorno D1: qualquer evento no dia seguinte ao da exposição.
    #
    # Coortes imaturas (expostas hoje) SAEM do denominador e vão para `pending`.
    # Contá-las como não-retorno afirmaria um fato que ainda não pôde acontecer.
    def d1_return_row
      per_variant = VARIANTS.to_h do |variant|
        mature, pending = exposures_by_variant.fetch(variant, []).partition do |row|
          ReportingTime.cohort_mature?(row[:exposed_at], 1)
        end
        returned = mature.count { |row| returned_on_d1?(row) }

        [
          variant,
          {
            cumulative: ratio(returned, mature.size, "post_onboarding_ab_d1_return_v1"),
            pending: pending.size
          }
        ]
      end

      {
        key: "d1_return",
        label: "Retorno D1",
        unit: "installations",
        variants: per_variant,
        difference: { cumulative: difference_between(per_variant.dig("account_gate", :cumulative), per_variant.dig("open_app", :cumulative)) },
        note: "Instalações expostas hoje ainda não puderam retornar e ficam fora do denominador."
      }
    end

    def returned_on_d1?(row)
      target = local_date(row[:exposed_at]) + 1
      events = first_event_at[row[:installation_id]] || {}

      events.values.any? { |at| at.present? && local_date(at) == target }
    end

    # Tempo até o primeiro treino. NÃO é MetricResult: não é razão, e forçá-lo
    # naquele formato faria "sample_size" significar outra coisa.
    def time_to_first_workout_row
      per_variant = VARIANTS.to_h do |variant|
        seconds = exposures_by_variant.fetch(variant, []).filter_map do |row|
          at = first_started_at(row)
          next nil if at.nil? || row[:exposed_at].nil? || at < row[:exposed_at]

          (at - row[:exposed_at]).to_i
        end.sort

        [ variant, { p50_seconds: percentile(seconds, 0.5), p90_seconds: percentile(seconds, 0.9), sample_size: seconds.size } ]
      end

      { key: "time_to_first_workout", label: "Tempo até o 1º treino", unit: "seconds", variants: per_variant }
    end

    def first_started_at(row)
      events = first_event_at[row[:installation_id]] || {}
      %w[workout_first_exercise_started workout_started].filter_map { |name| events[name] }.min
    end

    def percentile(sorted, fraction)
      return nil if sorted.empty?

      sorted[[ (sorted.size * fraction).ceil - 1, 0 ].max]
    end

    # ----------------------------------------------------------------- funis

    def funnels
      VARIANTS.map do |variant|
        rows = exposures_by_variant.fetch(variant, [])
        stages = FUNNELS.fetch(variant).map do |stage|
          count = stage[:events].empty? ? rows.size : rows.count { |row| reached?(row, stage[:events]) }
          { key: stage[:key], label: stage[:label], count: count,
            conversion_from_exposed: ratio(count, rows.size, STEP_DEFINITION) }
        end

        { variant: variant, label: VARIANT_LABELS[variant], exposed: rows.size,
          sample_warning: sample_warning(rows.size), stages: stages }
      end
    end

    # Última etapa alcançada por instalação, dentro do funil DA PRÓPRIA VARIANTE.
    # Cada instalação aparece em exatamente um balde.
    def last_stage
      VARIANTS.map do |variant|
        stages = FUNNELS.fetch(variant)
        rows = exposures_by_variant.fetch(variant, [])

        counts = Hash.new(0)
        rows.each do |row|
          index = stages.rindex { |stage| stage[:events].empty? || reached?(row, stage[:events]) }
          counts[stages[index][:key]] += 1
        end

        {
          variant: variant,
          label: VARIANT_LABELS[variant],
          buckets: stages.map { |stage| { key: stage[:key], label: stage[:label], count: counts[stage[:key]] } }
        }
      end
    end

    # ----------------------------------------------------------- guardrails

    def guardrails
      {
        # No topo de propósito: se este número não é zero, TODOS os outros estão
        # medindo uma população que não dá para reconstruir.
        events_missing_installation_id: events_missing_installation_id,
        variant_disagreement: exposures.values.count { |row| row[:variant_count] > 1 },
        generation_errors: generation_errors,
        claim_failures: claim_failures,
        auth_failures: VARIANTS.to_h { |variant| [ variant, count_reached_any(variant, ERROR_EVENTS) ] },
        no_plan_after_exposure: VARIANTS.to_h do |variant|
          [ variant, ratio(
            exposed_count(variant) - count_reached(variant, %w[workout_created], scope: :cumulative),
            exposed_count(variant),
            "post_onboarding_ab_no_plan_v1"
          ) ]
        end,
        hit_limit_rate: ratio(sessions_at_limit, exposed_count("open_app"), "post_onboarding_ab_hit_limit_v1"),
        gate_seen_later_rate: ratio(
          count_reached("open_app", %w[auth_screen_viewed], scope: :cumulative),
          exposed_count("open_app"),
          "post_onboarding_ab_gate_later_v1"
        )
      }
    end

    def count_reached_any(variant, event_names)
      exposures_by_variant.fetch(variant, []).count { |row| reached?(row, event_names) }
    end

    def events_missing_installation_id
      ProductAnalyticsEvent
        .where(event_name: [ EXPOSED_EVENT, ASSIGNED_EVENT ])
        .where("properties->>'experiment_key' = ?", EXPERIMENT_KEY)
        .where("properties->>'installation_id' IS NULL")
        .count
    end

    # Lido do BANCO e não de eventos do cliente: o cliente não enxerga uma falha
    # que aconteceu no servidor, então um funil baseado só nele reportaria zero
    # erro justamente quando a geração está quebrada.
    # Os três guardrails abaixo contam sobre instalações EXPOSTAS, não sobre a
    # coorte elegível: essa é a unidade declarada do painel, e é o que mantém cada
    # razão com numerador e denominador na mesma população.
    def generation_errors
      exposed = AppInstallation.where(installation_id: filtered_exposures.keys).select(:id)

      AnonymousOnboardingSession.where(app_installation_id: exposed)
                                .where(last_generation_status: "failed")
                                .count
    end

    def claim_failures
      exposed = AppInstallation.where(installation_id: filtered_exposures.keys).select(:id)

      AnonymousOnboardingSession.where(app_installation_id: exposed)
                                .where.not(last_claim_failure_code: [ nil, "" ])
                                .group(:last_claim_failure_code)
                                .count
    end

    # Só open_app, porque o denominador de hit_limit_rate é
    # exposed_count("open_app") — e account_gate mal chega a abrir uma sessão
    # anônima, então somá-la aqui inflaria a taxa com quem não podia contribuir.
    def sessions_at_limit
      exposed_open_app = AppInstallation.where(
        installation_id: exposures_by_variant.fetch("open_app", []).map { |row| row[:installation_id] }
      ).select(:id)

      AnonymousOnboardingSession.where(app_installation_id: exposed_open_app)
                                .at_limit
                                .count
    end

    # ------------------------------------------------------------ estatística

    def sample_warning(exposed)
      return "Amostra muito baixa — resultado apenas direcional" if exposed < SAMPLE_FLOOR_DIRECTIONAL
      return "Amostra baixa — não concluir ainda" if exposed < SAMPLE_FLOOR_STABLE

      "Leitura mais estável, ainda observacional"
    end

    # ------------------------------------------------------------- utilidades

    def definition_for(key) = "post_onboarding_ab_#{key}_v1"

    def ratio(numerator, denominator, definition)
      MetricResult.ratio(numerator: numerator, denominator: denominator, definition: definition).as_json
    end

    def window_clause(column)
      return "" unless window

      ApplicationRecord.sanitize_sql_array([ "AND #{column} >= ? AND #{column} <= ?", window.begin, window.end ])
    end

    # O corte de início do experimento, sobre o tempo do evento. Convive com o
    # window_clause: os dois são AND, então o piso efetivo é o mais tardio, que é
    # o que um filtro de período deve fazer.
    def started_clause(column)
      started = self.class.started_at
      return "" unless started

      ApplicationRecord.sanitize_sql_array([ "AND #{column} >= ?", started ])
    end

    def quote(value) = ApplicationRecord.connection.quote(value)

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    end

    def local_date(time) = time&.in_time_zone(ReportingTime.zone)&.to_date

    def definitions
      {
        experiment_key: EXPERIMENT_KEY,
        min_build: min_build,
        started_at: self.class.started_at&.iso8601,
        period: period,
        window_start: window&.begin&.iso8601,
        window_end: window&.end&.iso8601,
        variants: VARIANTS.map { |variant| { key: variant, label: VARIANT_LABELS[variant] } },
        metric_definitions: METRICS.map { |metric| metric.slice(:key, :label, :events) },
        funnel_definitions: FUNNELS.transform_values { |stages| stages.map { |s| s.slice(:key, :label, :events) } },
        unit_note: UNIT_NOTE,
        window_note: WINDOW_NOTE,
        readout_note: READOUT_NOTE
      }
    end
  end
end
