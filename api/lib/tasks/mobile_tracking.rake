namespace :mobile_tracking do
  desc "Backfill app_installations + users.activation_platform from device_tokens (reliable source). " \
       "DRY_RUN=true (default) reports without writing; DRY_RUN=false persists. Idempotent."
  task backfill_installations: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    report = MobileTracking::BackfillInstallations.new(dry_run: dry_run).call

    puts "[mobile_tracking:backfill_installations] #{dry_run ? 'DRY RUN (no writes)' : 'APPLIED'}"
    puts "  device_tokens scanned:          #{report.device_tokens_scanned}"
    puts "  app_installations created:      #{report.installations_created}"
    puts "  app_installations existing:     #{report.installations_existing}"
    puts "  activation_platform backfilled: #{report.activation_platform_backfilled}"
    puts ""
    puts "  Re-run with DRY_RUN=false to apply." if dry_run
  end
end
