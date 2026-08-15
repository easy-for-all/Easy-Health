require "rails_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "scripts/cron/install_cron.sh" do
  let(:repo_root) { Rails.root.parent }
  let(:script) { repo_root.join("scripts/cron/install_cron.sh").to_s }

  it "is idempotent, migrates known legacy lines, and preserves external cron entries" do
    Dir.mktmpdir do |dir|
      app_dir = File.join(dir, "Easy-Health")
      fakebin = File.join(dir, "bin")
      crontab_state = File.join(dir, "crontab")
      FileUtils.mkdir_p([ app_dir, fakebin ])
      File.write(File.join(app_dir, "docker-compose.prod.yml"), "services:\n  api:\n")
      File.write(crontab_state, legacy_crontab)
      install_fake_crontab(fakebin)
      install_fake_flock(fakebin)

      env = {
        "PATH" => "#{fakebin}:#{ENV.fetch('PATH')}",
        "CRONTAB_STATE" => crontab_state,
        "APP_DIR" => app_dir,
        "COMPOSE_FILE" => "docker-compose.prod.yml",
        "LOG_DIR" => "logs",
        "APPLY" => "1",
        "SKIP_RUNTIME_VALIDATION" => "1",
        "CRON_TZ_MODE" => "force"
      }

      run_script!(env)
      first = File.read(crontab_state)
      run_script!(env)
      second = File.read(crontab_state)

      expect(second).to eq(first)
      expect(second.scan("# BEGIN EASYHEALTH ORCHESTRATION").size).to eq(1)
      expect(second).to include("refresh_analytics")
      expect(second).to include("CRON_TZ=America/Sao_Paulo")
      expect(second).to include("bin/rails orchestration:relationship_daily")
      expect(second).to include("bin/rails orchestration:run_15min")
      expect(second).to include("bin/rails orchestration:retry_pending_make")
      expect(second).to include("logs/make_pending_retry.log")
      expect(second).not_to include("RelationshipDailyJob.new.perform")
      expect(second).not_to include("MakeWebhookClient.new.deliver")
      expect(second).not_to include("scheduled_workout_reminders:run")
    end
  end

  def legacy_crontab
    <<~CRON
      5 0 * * * refresh_analytics
      0 8 * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.yml exec api rails runner "RelationshipDailyJob.new.perform"
      */15 * * * * cd /home/easy/Easy-Health && rails runner "UserEvent.where(make_delivery_status: 'pending').where('created_at > ?', 1.hour.ago).find_each { |e| MakeWebhookClient.new.deliver(e) }"
      */15 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.yml exec -T api bin/rails orchestration:run_15min
      */15 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.yml exec -T api bin/rails scheduled_workout_reminders:run
    CRON
  end

  def install_fake_crontab(fakebin)
    path = File.join(fakebin, "crontab")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      set -euo pipefail
      if [ "${1:-}" = "-l" ]; then
        cat "$CRONTAB_STATE"
        exit 0
      fi
      if [ "${1:-}" = "-V" ]; then
        echo "cronie"
        exit 0
      fi
      cp "$1" "$CRONTAB_STATE"
    SH
    FileUtils.chmod(0o755, path)
  end

  def install_fake_flock(fakebin)
    path = File.join(fakebin, "flock")
    File.write(path, "#!/usr/bin/env bash\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  def run_script!(env)
    _out, err, status = Open3.capture3(env, script)
    expect(status).to be_success, err
  end
end
