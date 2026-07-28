require "rails_helper"
require "rake"

# The diagnostic task must describe the SAME reality as the admin panel:
# observed authenticated signals and user_id, never app_build as a proxy for
# "current tracking vs legacy". It is read-only and prints no personal data.
RSpec.describe "mobile_tracking tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("mobile_tracking:installation_metrics")
  end

  let(:task) { Rake::Task["mobile_tracking:installation_metrics"] }

  before { task.reenable }

  def install(**attrs)
    create(:app_installation, { platform: "android", native: true }.merge(attrs))
  end

  it "reports the operational rate from observed signals, with both link flows" do
    user = create(:user)
    other = create(:user)
    # New flow: linked_at written by LinkToUser.
    install(installation_id: "task-new", user: user,
            first_authenticated_request_at: 2.hours.ago, linked_at: 2.hours.ago,
            last_authenticated_at: 2.hours.ago)
    # Legacy: linked before the column existed — user_id, no linked_at.
    install(installation_id: "task-legacy", user: other,
            first_authenticated_request_at: 3.days.ago, linked_at: nil,
            last_authenticated_at: 3.days.ago)

    expect { task.invoke }.to output(
      /sinal autenticado:\s+2.*vinculadas atualmente:\s+2.*não vinculadas:\s+0/m
    ).to_stdout
  end

  it "counts the legacy link in the operational rate instead of as a failure" do
    task.reenable
    install(installation_id: "task-legacy-only", user: create(:user),
            first_authenticated_request_at: 3.days.ago, linked_at: nil,
            last_authenticated_at: 3.days.ago)

    expect { task.invoke }.to output(
      /vínculos do fluxo novo:\s+0.*vínculos legados observados:\s+1.*taxa operacional \(user_id\):\s+100\.0% \(1\/1\)/m
    ).to_stdout
  end

  it "never groups installations by build (no current/legacy build proxy)" do
    install(installation_id: "task-build", app_build: "45")

    expect { task.invoke }.not_to output(/TRACKING ATUAL|LEGADO \(antes do build|build \d+\+/).to_stdout
  end

  # The note is what stops a reader from misreading a legacy row as a defect, so
  # it must state both halves: linked_at covers only the new flow, AND a row
  # without it is expected rather than broken.
  it "explains that a legacy link has no linked_at and is not a failure" do
    expect { task.invoke }
      .to output(/apenas vínculos realizados pelo fluxo novo.*isso é esperado, não é falha/m).to_stdout
  end

  it "writes nothing" do
    install(installation_id: "task-readonly", user: create(:user),
            first_authenticated_request_at: 1.hour.ago)

    expect { expect { task.invoke }.to output.to_stdout }
      .not_to change { [ AppInstallation.count, AppInstallation.where.not(linked_at: nil).count ] }
  end

  it "prints no installation_id, e-mail or user id" do
    user = create(:user, email: "task-privacy@example.com")
    install(installation_id: "task-secret-id", user: user, first_authenticated_request_at: 1.hour.ago)

    expect { task.invoke }.not_to output(/task-secret-id|task-privacy@example\.com/).to_stdout
  end
end
