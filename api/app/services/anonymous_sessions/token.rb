module AnonymousSessions
  # Credencial de curta duração para o app usar os endpoints anônimos.
  #
  # POR QUE NÃO O installation_id CRU COMO CREDENCIAL. Ele é UUIDv4, então
  # adivinhar está fora de questão — o problema é outro: ele é TELEMETRIA por
  # construção. Viaja no header X-Installation-Id de toda requisição, está no
  # contexto do Sentry, nas properties de todo evento de analytics e é a chave
  # de agrupamento do painel admin inteiro. Promovê-lo a credencial faria cada
  # linha de log e cada evento de diagnóstico virar chave de escrita dos treinos
  # daquele aparelho — e, pior, torneira de OpenAI.
  #
  # O token separa as duas coisas: identificar (installation_id, que continua
  # público) e autorizar (este token, que expira e é revogável em massa trocando
  # VERSION). Sem gem nova: MessageVerifier já vem com o Rails.
  module Token
    PURPOSE = "anonymous_session".freeze
    PREFIX = "eh_anon.".freeze
    TTL = 24.hours
    VERSION = 1

    # Erros do vocabulário do chamador. Distinguir "expirou" de "não é válido"
    # importa: um manda renovar, o outro manda parar.
    Result = Struct.new(:valid, :session_id, :installation_hash, :reason, keyword_init: true) do
      def valid?
        valid
      end
    end

    module_function

    def verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key(PURPOSE, 32),
        digest: "SHA256",
        serializer: JSON
      )
    end

    def issue(session_id:, installation_id:, now: Time.current)
      payload = {
        "v" => VERSION,
        "sid" => session_id,
        # Não o id em claro: o token vive no dispositivo e em logs de proxy. O
        # hash basta para provar que o token pertence a ESTA instalação, que é
        # a única pergunta que a verificação faz.
        "iid" => fingerprint(installation_id),
        "exp" => (now + TTL).to_i
      }

      PREFIX + verifier.generate(payload)
    end

    def verify(raw, installation_id:, now: Time.current)
      token = raw.to_s.delete_prefix(PREFIX)
      return failure("missing_token") if token.blank?

      payload = verifier.verified(token)
      return failure("invalid_token") if payload.blank?
      return failure("invalid_token") if payload["v"] != VERSION
      return failure("expired_token") if payload["exp"].to_i <= now.to_i

      # O token só vale no aparelho que o pediu. Sem esta amarração, um token
      # vazado funcionaria em qualquer instalação e o limite de 3 viraria
      # "3 por token", não "3 por aparelho".
      return failure("installation_mismatch") if payload["iid"] != fingerprint(installation_id)

      Result.new(valid: true, session_id: payload["sid"], installation_hash: payload["iid"])
    rescue StandardError
      failure("invalid_token")
    end

    def fingerprint(installation_id)
      Digest::SHA256.hexdigest(installation_id.to_s)[0, 32]
    end

    def failure(reason)
      Result.new(valid: false, reason: reason)
    end

    def expires_at(now: Time.current)
      now + TTL
    end
  end
end
