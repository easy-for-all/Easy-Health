class ExerciseSetupGuideService
  def initialize(exercise)
    @exercise = exercise
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))

    prompt = <<~PROMPT
      Você é personal trainer. Responda em português brasileiro, de forma curta e direta.

      Exercício: "#{@exercise.name}"
      Músculo principal: #{@exercise.muscle_group || "geral"}

      Gere um guia prático no formato abaixo. Sem Markdown (sem #, **, *). Apenas texto limpo com as seções exatas:

      COMO FAZER
      1. [passo curto]
      2. [passo curto]
      3. [passo curto]
      4. [passo curto]
      5. [passo curto]

      CONFIGURAÇÃO INICIAL
      - [posição corpo/banco]
      - [posição mãos/pés]
      - [pegada/apoio]
      - [carga sugerida para iniciante]

      ERROS COMUNS
      - [erro 1]
      - [erro 2]
      - [erro 3]

      DICA PARA INICIANTE
      [uma frase curta e prática]

      Máximo de 2 linhas por item. Sem introdução. Sem conclusão.
    PROMPT

    cfg = AiConfig.for(:setup_guide)
    response = client.messages(parameters: {
      model:      cfg[:model],
      max_tokens: cfg[:max_tokens],
      messages: [{ role: "user", content: prompt }]
    })

    guide = response.dig("content", 0, "text").to_s.strip
    @exercise.update_column(:setup_guide, guide) if guide.present?
    guide
  rescue KeyError => e
    Rails.logger.error("ExerciseSetupGuideService: ANTHROPIC_API_KEY not set — #{e.message}")
    nil
  rescue => e
    Rails.logger.error("ExerciseSetupGuideService [#{e.class}]: #{e.message}")
    nil
  end
end
