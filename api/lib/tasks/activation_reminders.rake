namespace :activation_reminders do
  desc "Run the 2h activation reminder sweep (users who created a plan but haven't started a workout)"
  task run_2h: :environment do
    stats = ActivationReminder2hJob.perform_now
    puts "[activation_reminders:run_2h] #{stats.inspect}"
  end

  desc "Run the 24h activation reminder sweep (users who created a plan but haven't started a workout)"
  task run_24h: :environment do
    stats = ActivationReminder24hJob.perform_now
    puts "[activation_reminders:run_24h] #{stats.inspect}"
  end
end
