FactoryBot.define do
  # event_name must exist in config/analytics/events.yml — ProductAnalyticsEvent
  # validates it against the catalog, so an invented name fails loudly here too.
  #
  # installation_id rides inside properties, not in a column: that is the only
  # join key an anonymous pre-auth event has back to app_installations.
  factory :product_analytics_event do
    event_name { "app_opened" }
    event_version { 1 }
    occurred_at { Time.current }
    received_at { Time.current }
    platform { "android" }
    app_surface { "native_shell" }
    environment { "test" }
    properties { {} }

    transient do
      installation_id { nil }
    end

    after(:build) do |event, evaluator|
      if evaluator.installation_id.present?
        event.properties = (event.properties || {}).merge("installation_id" => evaluator.installation_id)
      end
    end
  end
end
