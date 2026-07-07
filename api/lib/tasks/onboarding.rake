namespace :onboarding do
  desc "Backfill onboarding_flow=legacy for users with a workout plan but no tracked onboarding flow"
  task backfill_legacy_flow: :environment do
    scope = User.where(onboarding_flow: nil).joins(:workout_plans).distinct
    total = scope.count
    updated = scope.update_all(onboarding_flow: "legacy")
    puts "Backfilled #{updated} of #{total} users as onboarding_flow=legacy."
  end
end
