Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      namespace :auth do
        post   "sign_up",  to: "registrations#create"
        post   "sign_in",  to: "sessions#create"
        delete "sign_out", to: "sessions#destroy"
        get    "me",       to: "sessions#show"
      end

      resource  :health_profile, only: [:show, :create, :update]
      patch     "health_profile", to: "health_profiles#update"

      get  "workout_plan",            to: "workout_plans#show"
      get  "workout_plan/today",      to: "workout_plans#today"
      get  "workout_days/:id",        to: "workout_plans#day"
      post "workout_plan/regenerate", to: "workout_plans#regenerate"

      resources :exercises, only: [:index]

      post "workout_day_exercises/:id/swap", to: "workout_day_exercises#swap"
      post "workout_days/:workout_day_id/exercises", to: "workout_day_exercises#create"

      resources :workout_sessions, only: [:index, :create] do
        collection { get :stats }
      end
    end
  end
end
