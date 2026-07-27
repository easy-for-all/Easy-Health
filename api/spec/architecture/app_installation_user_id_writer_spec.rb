require "rails_helper"

RSpec.describe "AppInstallation user writer boundary" do
  APP_ROOT = Rails.root.join("app").freeze
  ALLOWED_WRITER = Rails.root.join("app/services/app_installations/link_to_user.rb").to_s.freeze

  WRITER_PATTERNS = [
    /\b(?:install|installation|app_installation)\w*\.user\s*=/,
    /\b(?:install|installation|app_installation)\w*\.user_id\s*=/,
    /\b(?:install|installation|app_installation)\w*\.update(?:!|_column|_columns)?\([^)\n]*\buser_id\b/,
    /\bAppInstallation\.[^\n]*update_all\([^)\n]*\buser_id\b/
  ].freeze

  it "keeps app_installations.user_id writes inside AppInstallations::LinkToUser" do
    violations = Dir.glob(APP_ROOT.join("**/*.rb")).each_with_object([]) do |path, acc|
      next if path == ALLOWED_WRITER

      File.readlines(path).each_with_index do |line, index|
        next unless WRITER_PATTERNS.any? { |pattern| line.match?(pattern) }

        acc << "#{path.delete_prefix("#{Rails.root}/")}:#{index + 1}: #{line.strip}"
      end
    end

    expect(violations).to be_empty, <<~MESSAGE
      AppInstallation user linkage must go through AppInstallations::LinkToUser.
      Direct writer(s) found:
      #{violations.join("\n")}
    MESSAGE
  end
end
