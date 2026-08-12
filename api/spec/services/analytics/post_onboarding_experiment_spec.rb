require "rails_helper"

RSpec.describe Analytics::PostOnboardingExperiment do
  let(:experiment_key) { described_class::EXPERIMENT_KEY }

  def installation(id, build: "60", user: nil, created_at: nil)
    attrs = { installation_id: id, platform: "android", native: true, app_build: build, user: user }
    attrs[:created_at] = created_at if created_at
    AppInstallation.create!(**attrs)
  end

  def event(name, installation_id:, at:, properties: {})
    ProductAnalyticsEvent.create!(
      event_name: name,
      occurred_at: at,
      received_at: at,
      platform: "android",
      app_surface: "native_shell",
      environment: "test",
      properties: { "installation_id" => installation_id }.merge(properties)
    )
  end

  def expose(installation_id, variant:, at: 3.days.ago)
    event("experiment_exposed", installation_id: installation_id, at: at,
          properties: { "experiment_key" => experiment_key, "variant" => variant })
  end

  def result(**opts) = described_class.new(**opts).call

  def metric(payload, key) = payload[:metrics].find { |row| row[:key] == key }

  describe "the unit of measurement" do
    # Se a unidade fosse o evento, uma instalação animada valeria por sete.
    it "counts an installation once no matter how many events it fires" do
      installation("i-1")
      expose("i-1", variant: "open_app")
      7.times { |n| event("workout_started", installation_id: "i-1", at: 2.days.ago + n.minutes) }

      row = metric(result, "workout_started")

      expect(row[:variants]["open_app"][:cumulative][:numerator]).to eq(1)
      expect(row[:variants]["open_app"][:cumulative][:denominator]).to eq(1)
    end

    # Atribuídas incluem quem nunca chegou à bifurcação. Dividir por elas mediria
    # o abandono do wizard, não o efeito da variante.
    it "uses exposed installations as the denominator, not assigned ones" do
      installation("i-1")
      installation("i-2")
      event("experiment_assigned", installation_id: "i-1", at: 3.days.ago,
            properties: { "experiment_key" => experiment_key, "variant" => "open_app" })
      event("experiment_assigned", installation_id: "i-2", at: 3.days.ago,
            properties: { "experiment_key" => experiment_key, "variant" => "open_app" })
      expose("i-1", variant: "open_app")

      payload = result

      expect(payload[:header][:assigned_installations]).to eq(2)
      expect(payload[:header][:exposed_installations]).to eq(1)
      expect(metric(payload, "workout_started")[:variants]["open_app"][:cumulative][:denominator]).to eq(1)
    end
  end

  describe "the 24h window" do
    # A janela é de CADA instalação. Um corte global mediria durações diferentes
    # como se fossem a mesma coisa.
    it "is measured from that installation's own exposure" do
      installation("in-time")
      installation("too-late")
      expose("in-time", variant: "open_app", at: 5.days.ago)
      expose("too-late", variant: "open_app", at: 5.days.ago)

      event("workout_started", installation_id: "in-time", at: 5.days.ago + 23.hours)
      event("workout_started", installation_id: "too-late", at: 5.days.ago + 25.hours)

      row = metric(result, "workout_started")

      expect(row[:variants]["open_app"][:within_24h][:numerator]).to eq(1)
      expect(row[:variants]["open_app"][:cumulative][:numerator]).to eq(2)
    end

    # Um treino iniciado ANTES da exposição não foi causado por ela.
    it "ignores events that happened before the exposure" do
      installation("i-1")
      expose("i-1", variant: "open_app", at: 2.days.ago)
      event("workout_started", installation_id: "i-1", at: 4.days.ago)

      expect(metric(result, "workout_started")[:variants]["open_app"][:cumulative][:numerator]).to eq(0)
    end
  end

  # O corte de início vale sobre o momento do EVENTO, igual ao predicado do
  # cliente (Date.now() >= started_at). Cortar pela criação da instalação mediria
  # uma população que o app não trata.
  describe "the experiment start cut" do
    let(:started) { 5.days.ago }

    def with_start(&block) = with_env("ANDROID_POST_ONBOARDING_AB_STARTED_AT" => started.iso8601, &block)

    # O app é WebView de site remoto: as instalações que já existem recebem o
    # código novo assim que a web sobe, e são expostas de verdade.
    it "keeps an installation that predates the start but was exposed after it" do
      with_start do
        installation("veteran", created_at: started - 10.days)
        expose("veteran", variant: "open_app", at: started + 1.day)

        expect(result[:header][:exposed_installations]).to eq(1)
      end
    end

    it "leaves out an exposure that happened before the start" do
      with_start do
        installation("early")
        expose("early", variant: "open_app", at: started - 1.day)

        expect(result[:header][:exposed_installations]).to eq(0)
      end
    end

    # Um evento anterior à exposição não pode virar o primeiro e esconder o que
    # veio DEPOIS dela: a instalação contaria como "nunca gerou plano" tendo
    # gerado, e o viés não é simétrico entre os braços.
    it "does not let a pre-exposure event hide a later one" do
      with_start do
        installation("returning", created_at: started + 1.hour)
        event("workout_created", installation_id: "returning", at: started + 2.hours)
        expose("returning", variant: "open_app", at: started + 1.day)
        event("workout_created", installation_id: "returning", at: started + 2.days)

        row = metric(result, "plan_generated")

        expect(row[:variants]["open_app"][:cumulative][:numerator]).to eq(1)
      end
    end
  end

  describe "division by zero" do
    it "reports no_coverage instead of 0% when a variant has no exposure" do
      installation("i-1")
      expose("i-1", variant: "open_app")

      row = metric(result, "workout_started")

      expect(row[:variants]["account_gate"][:cumulative][:status]).to eq("no_coverage")
      expect(row[:variants]["account_gate"][:cumulative][:denominator]).to eq(0)
    end

    # Uma taxa de controle zerada não torna o tratamento infinitamente melhor,
    # torna a comparação impossível.
    it "returns nil for the relative difference instead of infinity" do
      installation("c-1")
      installation("t-1")
      expose("c-1", variant: "account_gate")
      expose("t-1", variant: "open_app")
      event("workout_started", installation_id: "t-1", at: 2.days.ago)

      difference = metric(result, "workout_started")[:difference][:cumulative]

      expect(difference[:absolute_pp]).to eq(100.0)
      expect(difference[:relative]).to be_nil
    end
  end

  describe "audience exclusions" do
    it "leaves internal and Test Lab accounts out by default" do
      internal = create(:user, email: "hello@easyhealth.art")
      robot = create(:user, email: "runner@cloudtestlabaccounts.com")
      installation("external")
      installation("internal", user: internal)
      installation("robot", user: robot)
      %w[external internal robot].each { |id| expose(id, variant: "open_app") }

      expect(result[:header][:exposed_installations]).to eq(1)
      expect(result(audience: "all")[:header][:exposed_installations]).to eq(3)
    end
  end

  describe "funnels" do
    it "keeps each variant inside its own path" do
      installation("gate-1")
      installation("open-1")
      expose("gate-1", variant: "account_gate")
      expose("open-1", variant: "open_app")
      event("auth_screen_viewed", installation_id: "gate-1", at: 2.days.ago)
      event("anonymous_plan_limit_reached", installation_id: "open-1", at: 2.days.ago)

      funnels = result[:funnels].index_by { |f| f[:variant] }

      gate_stage = funnels["account_gate"][:stages].find { |s| s[:key] == "gate_viewed" }
      open_stage = funnels["open_app"][:stages].find { |s| s[:key] == "limit_reached" }

      expect(gate_stage[:count]).to eq(1)
      expect(open_stage[:count]).to eq(1)
      # "limite atingido" não existe no caminho de account_gate, e vice-versa.
      expect(funnels["account_gate"][:stages].map { |s| s[:key] }).not_to include("limit_reached")
      expect(funnels["open_app"][:stages].map { |s| s[:key] }).not_to include("gate_viewed")
    end

    it "puts every installation in exactly one last-stage bucket" do
      installation("a")
      installation("b")
      expose("a", variant: "open_app")
      expose("b", variant: "open_app")
      event("workout_created", installation_id: "a", at: 2.days.ago)
      event("workout_completed", installation_id: "a", at: 2.days.ago + 1.hour)

      buckets = result[:last_stage].find { |s| s[:variant] == "open_app" }[:buckets]

      expect(buckets.sum { |b| b[:count] }).to eq(2)
      expect(buckets.find { |b| b[:key] == "workout_completed" }[:count]).to eq(1)
      expect(buckets.find { |b| b[:key] == "exposed" }[:count]).to eq(1)
    end
  end

  describe "guardrails" do
    # Este número invalida todos os outros: sem installation_id não há como
    # reconstruir a população.
    it "counts experiment events that arrived without an installation_id" do
      ProductAnalyticsEvent.create!(
        event_name: "experiment_exposed", occurred_at: 2.days.ago, received_at: 2.days.ago,
        platform: "android", app_surface: "native_shell", environment: "test",
        properties: { "experiment_key" => experiment_key, "variant" => "open_app" }
      )

      expect(result[:guardrails][:events_missing_installation_id]).to eq(1)
    end

    it "flags an installation that reported two different variants" do
      installation("split-brain")
      expose("split-brain", variant: "open_app", at: 3.days.ago)
      expose("split-brain", variant: "account_gate", at: 2.days.ago)

      expect(result[:guardrails][:variant_disagreement]).to eq(1)
      # A primeira exposição é a que vale: é a que já foi medida.
      expect(result[:header][:distribution].find { |d| d[:variant] == "open_app" }[:exposed]).to eq(1)
    end

    # O cliente não enxerga uma falha do servidor: um funil só de eventos do
    # cliente reportaria zero erro justamente quando a geração está quebrada.
    it "reads generation errors from the server, not from client events" do
      record = installation("i-1")
      expose("i-1", variant: "open_app")
      AnonymousOnboardingSession.create!(app_installation: record, last_generation_status: "failed")

      expect(result[:guardrails][:generation_errors]).to eq(1)
    end

    it "reports the share that hit the anonymous limit" do
      record = installation("i-1")
      expose("i-1", variant: "open_app")
      AnonymousOnboardingSession.create!(app_installation: record, plans_generated_count: 3)

      expect(result[:guardrails][:hit_limit_rate][:numerator]).to eq(1)
      expect(result[:guardrails][:hit_limit_rate][:denominator]).to eq(1)
    end

    # O denominador destas razões é a instalação EXPOSTA. Contar sessões da
    # coorte inteira poria numerador e denominador em populações diferentes.
    it "ignores sessions from installations that were never exposed" do
      exposed = installation("exposed")
      unexposed = installation("unexposed")
      expose("exposed", variant: "open_app")
      AnonymousOnboardingSession.create!(app_installation: exposed, plans_generated_count: 0)
      AnonymousOnboardingSession.create!(
        app_installation: unexposed, last_generation_status: "failed", plans_generated_count: 3
      )

      expect(result[:guardrails][:generation_errors]).to eq(0)
      expect(result[:guardrails][:hit_limit_rate][:numerator]).to eq(0)
    end
  end

  describe "D1 return" do
    # Contar uma coorte imatura como não-retorno afirmaria um fato que ainda não
    # pôde acontecer.
    it "keeps installations exposed today out of the denominator" do
      installation("today")
      expose("today", variant: "open_app", at: Analytics::ReportingTime.now)

      row = metric(result, "d1_return")

      expect(row[:variants]["open_app"][:cumulative][:denominator]).to eq(0)
      expect(row[:variants]["open_app"][:pending]).to eq(1)
    end
  end

  describe "sample warnings" do
    it "never declares a winner" do
      installation("i-1")
      expose("i-1", variant: "open_app")

      distribution = result[:header][:distribution].find { |d| d[:variant] == "open_app" }

      expect(distribution[:sample_warning]).to match(/apenas direcional/)
      expect(result[:definitions][:readout_note]).to match(/não declara vencedor/)
    end
  end

  describe "variant filter" do
    it "narrows the panel to a single arm" do
      installation("c-1")
      installation("t-1")
      expose("c-1", variant: "account_gate")
      expose("t-1", variant: "open_app")

      expect(result(variant: "open_app")[:header][:exposed_installations]).to eq(1)
      expect(result[:header][:exposed_installations]).to eq(2)
    end
  end
end
