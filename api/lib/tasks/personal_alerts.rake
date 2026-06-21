namespace :personal do
  desc "Create alerts for clients inactive for 7+ days"
  task check_inactive: :environment do
    PersonalClientRelationship.includes(:personal, :client)
      .where(status: "active")
      .find_each do |rel|
        client   = rel.client
        personal = rel.personal
        next unless client && personal

        last_session = client.workout_sessions.order(completed_at: :desc).first
        inactive_days = last_session ? ((Time.current - last_session.completed_at) / 1.day).floor : 999
        next unless inactive_days >= 7

        already_alerted = PersonalAlert.where(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "inactive_7_days"
        ).where("created_at > ?", 7.days.ago).exists?
        next if already_alerted

        PersonalAlert.create!(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "inactive_7_days",
          title:       "#{client.name.split.first} está #{inactive_days} dias sem treinar",
          body:        "Considere entrar em contato para manter a motivação."
        )
        puts "Alert: #{personal.name} → #{client.name} (#{inactive_days}d inativo)"
      end
  end

  desc "Create alerts for clients who completed their weekly goal"
  task check_weekly_goal: :environment do
    week_start = Time.current.beginning_of_week(:sunday)
    PersonalClientRelationship.includes(:personal, :client)
      .where(status: "active")
      .find_each do |rel|
        client   = rel.client
        personal = rel.personal
        next unless client && personal

        sessions_this_week = client.workout_sessions
          .where("completed_at >= ?", week_start).count
        next unless sessions_this_week >= 3

        already_alerted = PersonalAlert.where(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "weekly_goal_completed"
        ).where("created_at > ?", week_start).exists?
        next if already_alerted

        PersonalAlert.create!(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "weekly_goal_completed",
          title:       "#{client.name.split.first} completou a meta semanal!",
          body:        "#{sessions_this_week} treinos essa semana."
        )
        puts "Alert: #{personal.name} → #{client.name} (meta semanal)"
      end
  end

  desc "Create alerts for clients with high adherence (>= 80% last 30 days)"
  task check_high_adherence: :environment do
    PersonalClientRelationship.includes(:personal, :client)
      .where(status: "active")
      .find_each do |rel|
        client   = rel.client
        personal = rel.personal
        next unless client && personal

        sessions = client.workout_sessions.where("completed_at > ?", 30.days.ago).count
        adherence_pct = (sessions / 30.0 * 7).clamp(0, 100).round
        next unless adherence_pct >= 80

        already_alerted = PersonalAlert.where(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "high_adherence"
        ).where("created_at > ?", 14.days.ago).exists?
        next if already_alerted

        PersonalAlert.create!(
          personal_id: personal.id,
          client_id:   client.id,
          kind:        "high_adherence",
          title:       "#{client.name.split.first} está arrasando! #{adherence_pct}% de aderência",
          body:        "Excelente consistência nos últimos 30 dias."
        )
      end
  end

  desc "Run all personal trainer alert checks"
  task check_all: [:check_inactive, :check_weekly_goal, :check_high_adherence] do
    puts "All personal trainer alert checks completed."
  end
end
