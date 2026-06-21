namespace :fitness_intelligence do
  desc "Create or recalculate fitness profiles. Use USER_ID=<id> to target one user."
  task recalculate: :environment do
    scope = User.joins(:health_profile)
    scope = scope.where(id: ENV.fetch("USER_ID")) if ENV["USER_ID"].present?

    processed = 0
    failed = 0

    scope.find_each(batch_size: 100) do |user|
      profile = FitnessIntelligence::ProfileBuilder.new(user).call(source: "rake_backfill")
      processed += 1 if profile
    rescue StandardError => e
      failed += 1
      Rails.logger.error("[FitnessIntelligence] Backfill failed user_id=#{user.id}: #{e.class}: #{e.message}")
    end

    puts "Fitness intelligence recalculation complete: #{processed} processed, #{failed} failed."
  end
end
