# Isolated push diagnostic. Sends ONE FCM message to each active device token of a
# single user and prints the FCM response so you can tell exactly where the chain
# breaks. Safe to run in any environment: tokens are always masked and no secret is
# printed.
#
#   bin/rails "push:send_test[123]"
#   bin/rails "push:send_test[123,Título,Corpo da mensagem]"
#
# Reading the output (maps to the A–G scenarios):
#   A  no user rows / no device_tokens at all  -> token was never generated on device
#   B  device_tokens exist but none active      -> token reached backend but was disabled
#   C  status=failed error_code=UNREGISTERED/INVALID_ARGUMENT/SENDER_ID_MISMATCH
#                                               -> FCM rejected the token (dead) -> invalidated
#   C' status=failed error_code=not_configured  -> backend Firebase credential missing/invalid
#   D  status=sent                              -> FCM accepted; if the phone shows nothing,
#                                                  the break is on-device (channel/permission/OS)
#   E/F/G verified on the device (foreground/background/channel) via the runbook
namespace :push do
  desc "Send a test FCM push to a single user's active device tokens. Args: user_id[,title,body]"
  task :send_test, %i[user_id title body] => :environment do |_t, args|
    user_id = args[:user_id]
    abort "Usage: bin/rails \"push:send_test[USER_ID]\"" if user_id.blank?

    user = User.find_by(id: user_id)
    abort "❌ User ##{user_id} not found (scenario A: no such user)." if user.nil?

    title = args[:title].presence || "EasyHealth — teste de push"
    body  = args[:body].presence  || "Se você recebeu isto, o push está funcionando. 💪"

    puts "== push:send_test =="
    puts "user: ##{user.id} <#{user.email}>"
    puts "FirebasePushService.configured?: #{FirebasePushService.configured?}"
    unless FirebasePushService.configured?
      puts "❌ Backend Firebase credential ausente/inválida (FIREBASE_SERVICE_ACCOUNT_JSON[_BASE64])."
      puts "   Nada será enviado. Corrija a credencial de service-account no ambiente. (cenário C')"
    end
    puts "project_id: #{FirebasePushService.project_id || '(nenhum)'}"

    all_tokens    = user.device_tokens.order(created_at: :desc)
    active_tokens = all_tokens.select { |t| t.enabled? && t.invalidated_at.nil? }

    puts "device_tokens: total=#{all_tokens.size} active=#{active_tokens.size}"

    if all_tokens.empty?
      puts "❌ Nenhum device_token para este usuário."
      puts "   Cenário A/B: o token nunca foi gerado no aparelho ou nunca chegou ao backend."
      puts "   Verifique no app: permissão concedida + POST /api/v1/device_tokens (ver runbook)."
      next
    end

    if active_tokens.empty?
      puts "⚠️  Existem tokens, mas nenhum ativo (todos invalidados/desabilitados)."
      all_tokens.each do |t|
        puts "   - #{t.masked_token} platform=#{t.platform} enabled=#{t.enabled?} " \
             "invalidated_at=#{t.invalidated_at&.iso8601 || '-'} reason=#{t.invalidation_reason || '-'}"
      end
      puts "   Cenário B: reative registrando o token novamente no aparelho."
      next
    end

    service = FirebasePushService.new

    active_tokens.each do |device|
      result = service.deliver(
        token: device.token,
        title: title,
        body: body,
        data: { type: "diagnostic_test" }
      )

      line = "→ #{device.masked_token} platform=#{device.platform} " \
             "status=#{result.status} " \
             "message_id=#{result.message_id || '-'} " \
             "error_code=#{result.error_code || '-'}"
      puts line

      if result.sent?
        puts "  ✅ FCM aceitou (cenário D). Se o aparelho não exibir, o problema é on-device " \
             "(canal/permissão/OS) — ver runbook adb/logcat."
      elsif result.invalid_token
        device.invalidate!(result.error_code || "diagnostic_invalid")
        puts "  ❌ FCM recusou o token (cenário C). Token invalidado no banco."
      else
        puts "  ❌ Falha no envio (error_code=#{result.error_code}). Ver logs do FirebasePushService."
      end
    end

    puts "== fim =="
  end
end
