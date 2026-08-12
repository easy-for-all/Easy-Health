# frozen_string_literal: true

# Rails already refuses destructive tasks against a protected environment, but it
# only finds out after loading the full environment: it boots the app, connects,
# reads ar_internal_metadata and then raises ProtectedEnvironmentError. By then
# Sentry is initialized, so a mistyped RAILS_ENV pages the team with what looks
# like a production incident (see the Aug 2026 db:test:prepare false alarm).
#
# Refusing at task-definition time is both louder and quieter: the operator gets
# an actionable message instead of a stack trace, and nothing is reported.
#
# Rails.env only reads ENV["RAILS_ENV"], so it is available here without the
# :environment prerequisite — which is exactly what lets us drop that
# prerequisite and abort before anything boots.
if Rails.env.production?
  protected_test_tasks = %w[
    db:test:prepare
    db:test:load
    db:test:load_schema
    db:test:purge
    db:truncate_all
    db:schema:load
    db:migrate:reset
  ]

  protected_test_tasks.each do |task_name|
    next unless Rake::Task.task_defined?(task_name)

    task = Rake::Task[task_name]
    task.clear_actions
    task.clear_prerequisites
    task.enhance do
      abort <<~MESSAGE
        Refusing to run #{task_name} with RAILS_ENV=production.

        This task rebuilds or truncates a database and must never run against the
        production environment. Nothing was changed.

        If you meant to prepare the test database, set the environment explicitly:

            RAILS_ENV=test bin/rails #{task_name}

        Note that inside the API container RAILS_ENV is baked in as production
        (api/Dockerfile), so the prefix is required there.
      MESSAGE
    end
  end
end
