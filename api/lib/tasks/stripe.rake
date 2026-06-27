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

  # ---------------------------------------------------------------------------
  # Account migration: cancel old-account subscriptions and generate new
  # checkout links so customers re-subscribe in the new Stripe account.
  #
  # Usage:
  #   STRIPE_OLD_KEY=sk_live_OLD... rake stripe:migrate_customers
  #
  # The task uses STRIPE_OLD_KEY to cancel the old subscriptions and
  # ENV["STRIPE_SECRET_KEY"] (already set to the new account) to create
  # new checkout sessions.
  # ---------------------------------------------------------------------------
  desc "Migrate active customers from old Stripe account. Requires STRIPE_OLD_KEY env var."
  task migrate_customers: :environment do
    old_key = ENV.fetch("STRIPE_OLD_KEY") do
      abort "[ERROR] Set STRIPE_OLD_KEY=sk_live_OLD... before running this task."
    end

    active_subs = Subscription.where(status: %w[active trialing])
                              .includes(:user)
                              .order(:created_at)

    if active_subs.empty?
      puts "No active/trialing subscriptions found. Nothing to migrate."
      next
    end

    puts "\n#{"=" * 60}"
    puts "Customers to migrate (#{active_subs.count}):"
    puts "=" * 60
    active_subs.each do |sub|
      period_end = sub.current_period_end&.strftime("%Y-%m-%d") || "unknown"
      puts "  #{sub.user.email.ljust(40)} plan=#{sub.plan_name}  period_end=#{period_end}  sub_id=#{sub.stripe_subscription_id}"
    end

    puts "\nThis will:"
    puts "  1. Cancel each subscription in the OLD account (cancel_at_period_end: true)"
    puts "  2. Generate a NEW checkout link per customer (new account, no extra trial)"
    puts "  3. Print the link — you send it manually to each customer"
    puts "\nType YES to continue: "
    confirmation = $stdin.gets&.chomp
    abort "Aborted." unless confirmation == "YES"

    puts "\n#{"=" * 60}"
    puts "Results"
    puts "=" * 60

    active_subs.each do |sub|
      user  = sub.user
      email = user.email
      old_sub_id = sub.stripe_subscription_id

      print "  [#{email}] "

      # Step 1 — cancel in old account at period end (api_key overrides global key)
      begin
        if old_sub_id.present?
          Stripe::Subscription.update(
            old_sub_id,
            { cancel_at_period_end: true },
            { api_key: old_key }
          )
          print "cancelled old sub (at period end) | "
        else
          print "no old sub_id, skipping cancel | "
        end
      rescue Stripe::StripeError => e
        print "old cancel ERROR: #{e.message} | "
      end

      # Step 2 — create new checkout session in new account
      begin
        price_id = sub.pro_yearly? ? ENV.fetch("STRIPE_PRICE_PRO_YEARLY") : ENV.fetch("STRIPE_PRICE_PRO_MONTHLY")

        customer = Stripe::Customer.create(
          email: email,
          name: user.name,
          metadata: { user_id: user.id.to_s, migrated_from: sub.stripe_customer_id.to_s }
        )

        session = Stripe::Checkout::Session.create(
          customer: customer.id,
          mode: "subscription",
          line_items: [{ price: price_id, quantity: 1 }],
          subscription_data: { metadata: { user_id: user.id.to_s, plan: sub.plan_name } },
          metadata: { user_id: user.id.to_s, plan: sub.plan_name },
          success_url: "#{ENV.fetch('FRONTEND_URL', 'https://easyhealth.art')}/billing/success?session_id={CHECKOUT_SESSION_ID}",
          cancel_url: "#{ENV.fetch('FRONTEND_URL', 'https://easyhealth.art')}/pricing"
        )

        puts "OK"
        puts "    Checkout URL: #{session.url}"

        # Clear old Stripe IDs so webhook from new account can set new ones
        sub.update_columns(
          stripe_customer_id: customer.id,
          stripe_subscription_id: nil,
          status: "incomplete"
        )
      rescue Stripe::StripeError => e
        puts "checkout ERROR: #{e.message}"
      end
    end

    puts "\nDone. Send each URL above to the respective customer."
    puts "Their access remains active until the current period ends."
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
