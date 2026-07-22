require "rails_helper"

RSpec.describe Analytics::AndroidInstallations do
  subject(:result) { described_class.new.call }

  it "counts the real installed base from app_installations, not activation_platform" do
    user = create(:user)
    create(:app_installation, :authenticated, user: user, platform: "android", source: "register")
    create(:app_installation, :anonymous, platform: "android", source: "backfill_device_token")
    create(:app_installation, platform: "web", native: false) # excluded

    expect(result[:installations][:known]).to eq(2)
    expect(result[:installations][:authenticated]).to eq(1)
    expect(result[:installations][:anonymous]).to eq(1)
    expect(result[:installations][:registered_live]).to eq(1)
    expect(result[:installations][:backfilled]).to eq(1)
    expect(result[:users][:identified]).to eq(1)
  end

  it "computes tracking coverage as registered_live / known" do
    create(:app_installation, platform: "android", source: "register")
    create(:app_installation, platform: "android", source: "backfill_device_token")

    cov = result[:tracking_coverage]
    expect(cov.numerator).to eq(1)
    expect(cov.denominator).to eq(2)
  end

  it "builds an installation→completed funnel keyed on the Android install base" do
    user = create(:user)
    create(:app_installation, :authenticated, user: user, platform: "android")
    user.workout_plans.create!(active: true)

    labels = result[:funnel].map { |s| s[:label] }
    expect(labels.first).to eq("Instalação conhecida")
    known = result[:funnel].find { |s| s[:label] == "Instalação conhecida" }
    expect(known[:count]).to eq(1)
    created = result[:funnel].find { |s| s[:label] == "Treino criado" }
    expect(created[:count]).to eq(1)
  end

  it "lists versions with install counts" do
    create(:app_installation, platform: "android", app_version: "1.1.0")
    create(:app_installation, platform: "android", app_version: "1.1.0")
    create(:app_installation, platform: "android", app_version: "1.2.0")

    versions = result[:versions]
    top = versions.first
    expect(top[:app_version]).to eq("1.1.0")
    expect(top[:installations]).to eq(2)
  end
end
