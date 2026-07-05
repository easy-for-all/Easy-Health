namespace :account do
  desc "Restore an anonymized (soft-deleted) account by recovering its real email/name from " \
       "Stripe. One-off remediation for accounts that were anonymized before login-blocking " \
       "existed. Dry-run by default; pass CONFIRM=yes to write changes. " \
       "Usage: EMAIL=deleted_12@easyhealth.invalid rails account:restore " \
       "or USER_ID=12 rails account:restore"
  task restore: :environment do
    identifier = ENV["EMAIL"] || ENV["USER_ID"]
    abort "Usage: EMAIL=deleted_12@easyhealth.invalid rails account:restore (or USER_ID=12)" if identifier.blank?

    user = ENV["USER_ID"].present? ? User.find_by(id: ENV["USER_ID"]) : User.find_by(email: ENV["EMAIL"].downcase)
    abort "User not found: #{identifier}" unless user
    abort "User #{user.id} is not anonymized, nothing to restore." if user.anonymized_at.blank?

    sub = user.subscription
    abort "User #{user.id} has no subscription record to recover Stripe data from." unless sub
    abort "User #{user.id}'s subscription has no stripe_subscription_id — original " \
          "email/name can't be recovered from Stripe. Confirm details with the customer " \
          "directly instead of running this task." if sub.stripe_subscription_id.blank?

    stripe_subscription = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
    stripe_customer = Stripe::Customer.retrieve(stripe_subscription.customer)

    real_email = stripe_customer.email
    real_name  = stripe_customer.name.presence || user.name

    puts "Found Stripe customer for user ##{user.id}:"
    puts "  current (anonymized) email: #{user.email}"
    puts "  recovered email:            #{real_email}"
    puts "  recovered name:             #{real_name}"
    puts "  stripe_customer_id:         #{stripe_customer.id}"
    puts "  stripe subscription status: #{stripe_subscription.status}"

    if ENV["CONFIRM"] != "yes"
      puts "\nDry run only — no changes made. Re-run with CONFIRM=yes to apply."
      next
    end

    abort "Recovered email #{real_email} is already blocked, aborting." if BlockedEmail.blocked?(real_email) && !BlockedEmail.where(email: real_email.downcase.strip, user_id: user.id).exists?

    ActiveRecord::Base.transaction do
      BlockedEmail.where(email: real_email.downcase.strip, user_id: user.id).delete_all
      user.update_columns(name: real_name, email: real_email, anonymized_at: nil, deletion_requested_at: nil)
      sub.update_columns(stripe_customer_id: stripe_customer.id)
    end

    puts "\nRestored user ##{user.id}. They can sign in again with Google (provider/uid were never removed)."
  end
end
