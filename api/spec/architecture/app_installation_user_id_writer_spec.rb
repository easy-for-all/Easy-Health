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
        # A comment may legitimately name the forbidden shape while explaining
        # why it is forbidden.
        next if line.strip.start_with?("#")
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

  # The strongest guard: the patterns must still match the ONE legitimate
  # implementation. If LinkToUser is refactored into a shape they no longer
  # recognise, the allowlist above stops meaning anything and every other file
  # would pass for the wrong reason.
  it "still matches the real write inside LinkToUser" do
    writes = File.readlines(ALLOWED_WRITER).reject { |line| line.strip.start_with?("#") }
                 .select { |line| WRITER_PATTERNS.any? { |pattern| line.match?(pattern) } }

    expect(writes).not_to be_empty, <<~MESSAGE
      The writer patterns no longer match anything in link_to_user.rb.
      Either the service stopped writing user_id, or it was rewritten into a
      shape these patterns miss — in which case this whole check is blind and
      the patterns must be updated before trusting it again.
    MESSAGE
  end

  # Guards the guard: patterns that match nothing would make the check silently
  # useless, which is worse than not having it.
  it "still recognises a direct writer when one is introduced" do
    [
      "install.user = current_user",
      "installation.user_id = user.id",
      "install.update_columns(user_id: current_user.id)",
      "AppInstallation.where(id: ids).update_all(user_id: 1)"
    ].each do |sample|
      expect(WRITER_PATTERNS.any? { |pattern| sample.match?(pattern) })
        .to be(true), "no pattern matched: #{sample}"
    end
  end
end
