module Observability
  # Applies the bi_observability_* SQL views from api/db/views/*.sql.
  #
  # WHY THIS EXISTS AT ALL: db/schema.rb is Ruby-format, and the Ruby schema
  # dumper does not emit views. So a database created with `db:schema:load`
  # (every fresh dev machine, every CI run, and rails_helper's
  # maintain_test_schema!) would have the tables but none of the views, while
  # production — built by db:migrate — would have them. That divergence is
  # silent and only shows up as a spec that passes locally and fails in CI.
  #
  # The fix is to make view creation idempotent (CREATE OR REPLACE) and run it
  # from all three places: the migration, the deploy, and the spec suite. See
  # docs/observability/BI_VIEWS.md.
  #
  # Versioned filenames (_v01) follow the Scenic convention without the gem: to
  # change a view, add _v02.sql and leave the old file as the record of what
  # production had before.
  module BiViews
    VIEWS_PATH = Rails.root.join("db", "views")
    PREFIX = "bi_observability_".freeze

    module_function

    # @return [Hash] view_name => sql, highest version per view
    def definitions
      Dir.glob(VIEWS_PATH.join("#{PREFIX}*_v*.sql")).each_with_object({}) do |path, acc|
        basename = File.basename(path, ".sql")
        name, version = basename.match(/\A(.+)_v(\d+)\z/)&.captures
        next if name.nil?

        existing = acc[name]
        next if existing && existing[:version] >= version.to_i

        acc[name] = { version: version.to_i, sql: File.read(path) }
      end
    end

    def view_names
      definitions.keys.sort
    end

    # @return [Array<String>] names applied, in order
    def apply!(skip_unready: false)
      # Views here read base tables only — never each other — so ordering does
      # not matter and a pg_restore cannot hit a dependency cycle.
      definitions.sort.filter_map do |name, definition|
        next if skip_unready && !ready?(name)

        ActiveRecord::Base.connection.execute(definition[:sql])
        name
      end
    end

    def drop!
      view_names.reverse.map do |name|
        ActiveRecord::Base.connection.execute("DROP VIEW IF EXISTS #{ActiveRecord::Base.connection.quote_table_name(name)}")
        name
      end
    end

    # @return [Array<String>] view names actually present in the database
    def verify!
      ActiveRecord::Base.connection.select_values(
        ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, PREFIX.length, PREFIX ])
          SELECT viewname FROM pg_views
          WHERE schemaname = ANY (current_schemas(false))
            AND LEFT(viewname, ?) = ?
          ORDER BY viewname
        SQL
      )
    end

    def ready?(name)
      return true unless name == "bi_observability_android_build_daily"

      ActiveRecord::Base.connection.column_exists?(:app_installations, :first_authenticated_request_at)
    end
  end
end
