require "rails_helper"

RSpec.describe Observability::Headers do
  def headers(hash)
    ActionDispatch::Http::Headers.from_hash(
      hash.transform_keys { |k| "HTTP_#{k.tr('-', '_').upcase}" }
    )
  end

  describe ".identifier" do
    it "accepts a well-formed opaque id" do
      value = described_class.identifier(headers("X-Installation-Id" => "abc-123_DEF.4:5"), described_class::INSTALLATION)

      expect(value).to eq("abc-123_DEF.4:5")
    end

    it "truncates before validating so an over-long value cannot reach a dimension" do
      long = "a" * 200
      value = described_class.identifier(headers("X-Session-Id" => long), described_class::SESSION)

      expect(value.length).to eq(described_class::IDENTIFIER_MAX)
    end

    # The installation header is bounded by what the register endpoint accepts,
    # not by the generic dimension limit: an id the backend stored has to stay
    # findable here, or reconciliation would create rows it can never link.
    it "allows the installation id the full length the register endpoint accepts" do
      long = "a" * 200
      value = described_class.identifier(headers("X-Installation-Id" => long), described_class::INSTALLATION)

      expect(value.length).to eq(AppInstallation::INSTALLATION_ID_MAX_BYTES)
      expect(AppInstallation::INSTALLATION_ID_MAX_BYTES).to be > described_class::IDENTIFIER_MAX
    end

    it "rejects rather than sanitizes a hostile value" do
      hostile = "abc<script>alert(1)</script>"
      value = described_class.identifier(headers("X-Installation-Id" => hostile), described_class::INSTALLATION)

      # Dropped entirely — a "cleaned up but kept" value is how injected input
      # ends up in a label.
      expect(value).to be_nil
    end

    it "returns nil for a blank header" do
      expect(described_class.identifier(headers("X-Installation-Id" => "   "), described_class::INSTALLATION)).to be_nil
      expect(described_class.identifier(headers({}), described_class::INSTALLATION)).to be_nil
    end
  end

  describe ".platform" do
    it "accepts a known platform, case-insensitively" do
      expect(described_class.platform(headers("X-Platform" => "Android"))).to eq("android")
    end

    it "collapses an unknown platform into 'unknown' instead of trusting it" do
      expect(described_class.platform(headers("X-Platform" => "nintendo"))).to eq("unknown")
    end

    it "returns nil when absent" do
      expect(described_class.platform(headers({}))).to be_nil
    end
  end

  describe ".app_version" do
    it "accepts a dotted numeric version" do
      expect(described_class.app_version(headers("X-App-Version" => "1.0.51"))).to eq("1.0.51")
    end

    it "rejects a free-form string" do
      expect(described_class.app_version(headers("X-App-Version" => "v1.0-beta"))).to be_nil
    end
  end

  describe ".app_build" do
    it "accepts digits" do
      expect(described_class.app_build(headers("X-App-Build" => "51"))).to eq("51")
    end

    it "rejects anything that is not digits" do
      expect(described_class.app_build(headers("X-App-Build" => "51-rc1"))).to be_nil
      expect(described_class.app_build(headers("X-App-Build" => "1234567890123"))).to be_nil
    end
  end
end
