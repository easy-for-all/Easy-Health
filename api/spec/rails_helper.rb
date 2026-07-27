require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("Running in production!") if Rails.env.production?
require "rspec/rails"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

Warden.test_mode!

RSpec.configure do |config|
  # db/schema.rb is Ruby-format and the Ruby dumper cannot represent views, so a
  # test database built from the schema has the observability tables but none of
  # the bi_observability_* views. Applying them here keeps test, development and
  # production in agreement. Idempotent (CREATE OR REPLACE).
  # See api/lib/observability/bi_views.rb and docs/observability/BI_VIEWS.md.
  config.before(:suite) do
    Observability::BiViews.apply!
  rescue StandardError => e
    warn "[observability] could not apply BI views to the test database: #{e.class}: #{e.message}"
  end

  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include Warden::Test::Helpers
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.after { Warden.test_reset! }
end
