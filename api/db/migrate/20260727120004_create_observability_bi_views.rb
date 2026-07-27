# Creates the bi_observability_* SQL views from api/db/views/*.sql.
#
# IMPORTANT — db/schema.rb DOES NOT CONTAIN THESE VIEWS. The schema format is
# :ruby and the Ruby dumper cannot represent views, so a database built with
# `db:schema:load` (fresh dev machine, CI, rails_helper's maintain_test_schema!)
# gets the tables and none of the views.
#
# That gap is closed by applying them idempotently from three places:
#   * this migration                       (production, via db:migrate)
#   * rake observability:bi_views:apply    (manual / deploy step)
#   * spec/rails_helper.rb before(:suite)  (test suite)
#
# CREATE OR REPLACE makes triple application free. See docs/observability/BI_VIEWS.md.
class CreateObservabilityBiViews < ActiveRecord::Migration[8.1]
  def up
    Observability::BiViews.apply!(skip_unready: true)
  end

  def down
    Observability::BiViews.drop!
  end
end
