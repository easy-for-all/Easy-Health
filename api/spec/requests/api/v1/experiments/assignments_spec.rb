require "rails_helper"

RSpec.describe "Api::V1::Experiments::Assignments", type: :request do
  let(:experiment_key) { Analytics::ExperimentRegistry::ANDROID_POST_ONBOARDING_GATE }

  def assign(overrides = {})
    post "/api/v1/experiments/assignments",
         params: {
           experiment_key: experiment_key,
           variant: "open_app",
           installation_id: "install-req-1"
         }.merge(overrides),
         as: :json
  end

  it "records the assignment for an anonymous installation" do
    assign

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body["status"]).to eq("assigned")
    expect(response.parsed_body["variant"]).to eq("open_app")

    row = Analytics::ExperimentAssignment.last
    expect(row.experiment_key).to eq(experiment_key)
    expect(row.installation_id).to eq("install-req-1")
    expect(row.variant).to eq("open_app")
    expect(row.assigned_at).to be_present
    # user_id fica NULL de propósito: o índice único por instalação só cobre
    # user_id IS NULL, então carimbar o usuário aqui desligaria o dedup.
    expect(row.user_id).to be_nil
  end

  it "is idempotent for the same installation" do
    3.times { assign }

    expect(Analytics::ExperimentAssignment.for_experiment(experiment_key).count).to eq(1)
  end

  # A variante local é decidida por hash síncrono; o banco é só o desempate. Se
  # as duas discordarem, ganha a que já teve exposição medida.
  it "answers with the stored variant when the client sends a different one" do
    assign(variant: "open_app")
    assign(variant: "account_gate")

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body["status"]).to eq("conflict")
    expect(response.parsed_body["variant"]).to eq("open_app")
    expect(Analytics::ExperimentAssignment.for_experiment(experiment_key).pluck(:variant)).to eq([ "open_app" ])
  end

  it "keeps two installations in their own rows" do
    assign(installation_id: "install-a")
    assign(installation_id: "install-b")

    expect(Analytics::ExperimentAssignment.for_experiment(experiment_key).count).to eq(2)
  end

  describe "input the panel could not read" do
    # Sem allowlist, um cliente qualquer poderia semear chaves e variantes
    # arbitrárias numa tabela com índice único — o banco deduplicaria lixo com
    # a mesma fidelidade, e o painel dividiria por ele.
    it "ignores an unknown experiment key" do
      assign(experiment_key: "made_up_experiment")

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("ignored")
      expect(Analytics::ExperimentAssignment.count).to eq(0)
    end

    it "ignores a variant outside the registry" do
      assign(variant: "third_arm")

      expect(response.parsed_body["status"]).to eq("ignored")
      expect(Analytics::ExperimentAssignment.count).to eq(0)
    end

    it "ignores a blank installation_id" do
      assign(installation_id: "")

      expect(response.parsed_body["status"]).to eq("ignored")
      expect(Analytics::ExperimentAssignment.count).to eq(0)
    end

    it "ignores an oversized installation_id" do
      assign(installation_id: "x" * 200)

      expect(response.parsed_body["status"]).to eq("ignored")
      expect(Analytics::ExperimentAssignment.count).to eq(0)
    end
  end

  # Nunca bloqueia o cliente: a variante já está decidida localmente e uma falha
  # aqui não pode mudar o que a pessoa está vendo.
  it "still accepts when the write blows up" do
    allow(Analytics::ExperimentAssignment).to receive(:create!).and_raise(StandardError, "boom")

    assign

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body["status"]).to eq("ignored")
  end

  it "works the same with a signed-in session" do
    user = create(:user)
    sign_in user

    assign

    expect(response).to have_http_status(:accepted)
    expect(Analytics::ExperimentAssignment.last.user_id).to be_nil
  end
end
