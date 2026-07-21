require "rails_helper"
require "rake"

RSpec.describe "communication_events tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("communication_events:audit")
  end

  let(:audit_task) { Rake::Task["communication_events:audit"] }
  let(:preview_task) { Rake::Task["communication_events:preview"] }
  let(:user) { create(:user, marketing_consent: true, email: "ce-task@example.com") }

  before do
    audit_task.reenable
    preview_task.reenable
  end

  it "audits every configured event and reports them valid" do
    expect { audit_task.invoke }
      .to output(/trial_day_3.*lifecycle.*valid/m).to_stdout
  end

  it "previews a canonical schema 2 payload without persisting" do
    user

    expect do
      expect { preview_task.invoke("trial_day_3", user.email) }
        .to output(/"schema_version": 2.*"channels".*"email".*"template_key": "trial_day_3"/m).to_stdout
    end.not_to change(UserEvent, :count)
  end
end
