class ExerciseSetupGuideService
  def initialize(exercise)
    @exercise = exercise
  end

  def call
    client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))

    prompt = <<~PROMPT
      Você é um personal trainer certificado com experiência em ensinar iniciantes.

      Para o exercício "#{@exercise.name}" (grupo muscular: #{@exercise.muscle_group || "não especificado"}), escreva um guia de configuração completo para alguém que nunca usou esse equipamento.

      O guia deve conter exatamente estas seções numeradas:
      1. Equipamento necessário
      2. Ajuste do banco ou assento (altura, distância, inclinação — seja específico com detalhes práticos)
      3. Posição dos pés e pernas (onde apoiar, ângulo dos joelhos, largura)
      4. Posição das mãos e pegada (largura, tipo de pegada, pressão dos dedos)
      5. Postura do corpo (coluna, ombros, cabeça, contração do abdômen)
      6. Como se posicionar antes do primeiro movimento
      7. Erros comuns de iniciantes e como evitá-los

      Escreva em português brasileiro, de forma clara e direta, usando linguagem simples. Seja muito específico — imagine que a pessoa está sentada no aparelho agora e nunca fez isso antes.
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
