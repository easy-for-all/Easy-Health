FactoryBot.define do
  factory :ai_prompt_version do
    sequence(:name) { |n| "prompt_#{n}" }
    version         { "v1" }
    prompt_type     { "user" }
    content         { "Persona: {{persona}}\nArchetype: {{archetype}}\nBehavior: {{behavior}}" }
    active          { false }
    metadata        { {} }
  end
end
