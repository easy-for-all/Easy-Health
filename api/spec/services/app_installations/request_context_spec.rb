require "rails_helper"

RSpec.describe AppInstallations::RequestContext do
  def context_for(headers = {})
    described_class.from(ActionDispatch::TestRequest.create(headers))
  end

  describe "installation_id" do
    it "reads and exposes a valid header" do
      context = context_for("HTTP_X_INSTALLATION_ID" => "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0")

      expect(context).to be_present
      expect(context.installation_id).to eq("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0")
    end

    it "is absent when the header is missing or blank" do
      expect(context_for).not_to be_present
      expect(context_for("HTTP_X_INSTALLATION_ID" => "   ").installation_id).to be_nil
    end

    it "drops a hostile value instead of cleaning it up" do
      expect(context_for("HTTP_X_INSTALLATION_ID" => "abc<script>").installation_id).to be_nil
      expect(context_for("HTTP_X_INSTALLATION_ID" => "a b c").installation_id).to be_nil
    end

    it "accepts an id as long as the register endpoint allows" do
      long_id = "a" * AppInstallation::INSTALLATION_ID_MAX_BYTES

      expect(context_for("HTTP_X_INSTALLATION_ID" => long_id).installation_id).to eq(long_id)
    end
  end

  describe "runtime_context" do
    it "maps the platform header onto the allowlist" do
      expect(context_for("HTTP_X_PLATFORM" => "android").runtime_context).to eq("android_native")
      expect(context_for("HTTP_X_PLATFORM" => "web").runtime_context).to eq("web")
      expect(context_for("HTTP_X_PLATFORM" => "pwa").runtime_context).to eq("pwa")
    end

    it "falls back to unknown for a missing or unrecognised platform" do
      expect(context_for.runtime_context).to eq("unknown")
      expect(context_for("HTTP_X_PLATFORM" => "ios").runtime_context).to eq("unknown")
      expect(context_for("HTTP_X_PLATFORM" => "linux").runtime_context).to eq("unknown")
    end

    it "only reports native for the Android shell" do
      expect(context_for("HTTP_X_PLATFORM" => "android")).to be_native
      expect(context_for("HTTP_X_PLATFORM" => "web")).not_to be_native
      expect(context_for).not_to be_native
    end

    it "produces a value the model accepts" do
      %w[android web pwa linux].each do |platform|
        runtime = context_for("HTTP_X_PLATFORM" => platform).runtime_context
        expect(AppInstallation::RUNTIME_CONTEXTS).to include(runtime)
      end
    end
  end

  describe "build_number" do
    # Descriptive metadata only. No caller may branch on it: the Android shell
    # loads a remote web bundle, so the build says nothing about the header.
    it "exposes a numeric build and drops anything else" do
      expect(context_for("HTTP_X_APP_BUILD" => "47").build_number).to eq("47")
      expect(context_for("HTTP_X_APP_BUILD" => "unknown").build_number).to be_nil
      expect(context_for.build_number).to be_nil
    end

    it "does not influence presence or runtime" do
      legacy = context_for("HTTP_X_INSTALLATION_ID" => "abc", "HTTP_X_PLATFORM" => "android", "HTTP_X_APP_BUILD" => "34")
      current = context_for("HTTP_X_INSTALLATION_ID" => "abc", "HTTP_X_PLATFORM" => "android", "HTTP_X_APP_BUILD" => "47")

      expect(legacy.installation_id).to eq(current.installation_id)
      expect(legacy.runtime_context).to eq(current.runtime_context)
      expect(legacy).to be_present
      expect(current).to be_present
    end
  end

  describe "installation_id_hash" do
    it "is a short digest, never the raw id" do
      context = context_for("HTTP_X_INSTALLATION_ID" => "device-abc")

      expect(context.installation_id_hash.length).to eq(12)
      expect(context.installation_id_hash).not_to include("device-abc")
    end

    it "is nil without an id" do
      expect(context_for.installation_id_hash).to be_nil
    end
  end

  it "never raises, whatever the request looks like" do
    broken = double("request")
    allow(broken).to receive(:headers).and_raise(StandardError, "boom")

    expect { described_class.from(broken) }.not_to raise_error
    expect(described_class.from(broken)).not_to be_present
  end
end
