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

  # Reusable, guarded push test bench. All sends/mutations target the admin user
  # resolved from EMAIL only (PushTest.resolve_admin! refuses non-admins). See
  # app/services/push_test.rb.
  #
  #   bin/rails "push:test:inspect_user[mail.marcus.reis@gmail.com]"   # read-only
  #   bin/rails "push:test:inspect_environment"
  #   bin/rails "push:test:send_now[mail.marcus.reis@gmail.com]"
  #   bin/rails "push:test:schedule[mail.marcus.reis@gmail.com,2]"
  #   bin/rails "push:test:run_scheduler[mail.marcus.reis@gmail.com]"
  #   bin/rails "push:test:run_dispatcher[mail.marcus.reis@gmail.com]"
  #   bin/rails "push:test:invalidate_fake_token[mail.marcus.reis@gmail.com]"
  #   bin/rails "push:test:report[mail.marcus.reis@gmail.com]"
  namespace :test do
    desc "Read-only diagnostic of a user's push setup (+ near-match detection). Args: email"
    task :inspect_user, %i[email] => :environment do |_t, args|
      PushTest.inspect_user(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Print environment/config diagnostics (flags, firebase, cron hints)."
    task inspect_environment: :environment do
      PushTest.inspect_environment
    end

    desc "Send the standard admin test push now to the admin user's own tokens. Args: email"
    task :send_now, %i[email] => :environment do |_t, args|
      PushTest.send_now(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Create a reversible due delivery in N minutes to exercise the queue. Args: email,minutes"
    task :schedule, %i[email minutes] => :environment do |_t, args|
      PushTest.schedule(args[:email], args[:minutes])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Run the real eligibility scheduler scoped to one admin user. Args: email"
    task :run_scheduler, %i[email] => :environment do |_t, args|
      PushTest.run_scheduler(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Run the real dispatcher for one admin user's due deliveries. Args: email"
    task :run_dispatcher, %i[email] => :environment do |_t, args|
      PushTest.run_dispatcher(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Prove token invalidation on an isolated fake token (no real token touched). Args: email"
    task :invalidate_fake_token, %i[email] => :environment do |_t, args|
      PushTest.invalidate_fake_token(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end

    desc "Consolidated push report for a user (read-only). Args: email"
    task :report, %i[email] => :environment do |_t, args|
      PushTest.report(args[:email])
    rescue PushTest::Abort => e
      abort e.message
    end
  end
end
