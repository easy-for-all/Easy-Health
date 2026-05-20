namespace :stripe do
  desc "Sync a user's subscription from Stripe by email. Usage: rake stripe:sync_user[email@example.com]"
  task :sync_user, [:email] => :environment do |_, args|
    email = args[:email]
    abort "Usage: rake stripe:sync_user[email@example.com]" if email.blank?

    user = User.find_by(email: email)
    abort "User not found: #{email}" unless user

    puts "Syncing Stripe subscription for #{user.email} (id=#{user.id})..."

    result = StripeSyncService.call(user: user)

    if result.success
      puts "✓ #{result.message}"
      sub = result.subscription
      puts "  plan=#{sub.plan_name} status=#{sub.status} period_end=#{sub.current_period_end}"
    else
      puts "✗ #{result.message}"
      exit 1
    end
  end

  desc "List all StripeEvents processed. Usage: rake stripe:events[50]"
  task :events, [:limit] => :environment do |_, args|
    limit = (args[:limit] || 20).to_i
    events = StripeEvent.order(processed_at: :desc).limit(limit)
    puts "Last #{limit} processed Stripe events:"
    events.each do |e|
      puts "  #{e.processed_at.strftime('%Y-%m-%d %H:%M:%S')}  #{e.event_type.ljust(45)}  #{e.stripe_event_id}"
    end
  end
end
