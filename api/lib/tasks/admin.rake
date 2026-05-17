namespace :admin do
  desc "Promote an existing user to admin. Usage: rails admin:promote[email@example.com]"
  task :promote, [:email] => :environment do |_, args|
    email = args[:email] || ENV["ADMIN_EMAIL"]
    abort "Usage: rails admin:promote[email@example.com]" if email.blank?

    user = User.find_by(email: email.downcase)
    abort "User not found: #{email}" unless user

    user.update!(admin: true)
    puts "User #{user.email} is now an admin."
  end

  desc "Create a new admin user. Usage: rails admin:create[email@example.com,password]"
  task :create, [:email, :password] => :environment do |_, args|
    email    = args[:email]    || ENV["ADMIN_EMAIL"]
    password = args[:password] || ENV["ADMIN_PASSWORD"]
    abort "Usage: rails admin:create[email@example.com,password]" if email.blank? || password.blank?

    user = User.find_by(email: email.downcase)
    if user
      user.update!(admin: true, password: password)
      puts "Existing user #{user.email} updated and promoted to admin."
    else
      user = User.create!(
        name:     "Admin",
        email:    email.downcase,
        password: password,
        admin:    true
      )
      puts "Admin user created: #{user.email}"
    end
  end
end
