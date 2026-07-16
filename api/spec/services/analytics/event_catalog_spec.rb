require "rails_helper"

RSpec.describe Analytics::EventCatalog do
  it "loads the canonical taxonomy" do
    expect(described_class.names).to include("workout_completed", "app_first_open", "signup_completed")
    expect(described_class.taxonomy_version).to be_a(Integer)
  end

  it "knows which events are server-tracked" do
    expect(described_class.server_tracked).to include("workout_completed")
    # A GA4-only event is not server-tracked.
    expect(described_class.server_tracked).not_to include("home_viewed")
  end

  it "rejects unknown events" do
    expect(described_class.known?("workout_completed")).to be(true)
    expect(described_class.known?("definitely_not_an_event")).to be(false)
  end

  it "exposes the current version of an event" do
    expect(described_class.current_version("workout_completed")).to be >= 1
  end

  it "validates dimension enums" do
    expect(described_class.valid_platform?("android")).to be(true)
    expect(described_class.valid_platform?("mainframe")).to be(false)
    expect(described_class.valid_app_surface?("native_shell")).to be(true)
    expect(described_class.valid_environment?("production")).to be(true)
  end
end
