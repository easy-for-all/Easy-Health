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
        delete "account",  to: "registrations#destroy"

        scope "/password" do
          post "forgot", to: "passwords#forgot"
          post "reset",  to: "passwords#reset"
        end
      end

      resource  :health_profile, only: [:show, :create, :update]
      patch     "health_profile", to: "health_profiles#update"

      get  "workout_plans",              to: "workout_plans#index"
      get  "workout_plan",              to: "workout_plans#show"
      get  "workout_plan/today",        to: "workout_plans#today"
      get  "workout_days/:id",          to: "workout_plans#day"
      post "workout_plan/regenerate",   to: "workout_plans#regenerate"
      post "quick_workouts",            to: "quick_workouts#create"
      post "workout_days/:id/duplicate",       to: "workout_plans#duplicate_day"
      patch "workout_days/:id/toggle_favorite", to: "workout_days#toggle_favorite"
      patch "workout_days/:id/rename",          to: "workout_days#rename"

      resources :exercises, only: [:index] do
        collection { post :ai_substitute }
        member do
          get  :setup_guide
          post :favorite,   to: "user_favorite_exercises#create"
          delete :favorite, to: "user_favorite_exercises#destroy"
        end
      end
      get "exercises/favorites", to: "user_favorite_exercises#index"

      post   "workout_day_exercises/:id/swap", to: "workout_day_exercises#swap"
      patch  "workout_day_exercises/:id",      to: "workout_day_exercises#update"
      delete "workout_day_exercises/:id",      to: "workout_day_exercises#destroy"
      post   "workout_days/:workout_day_id/exercises",        to: "workout_day_exercises#create"
      patch  "workout_days/:workout_day_id/exercises/reorder", to: "workout_day_exercises#reorder"

      resources :workout_sessions, only: [:index, :create, :update] do
        collection do
          get :stats
          get :personal_records
          get :today
        end
      end

      patch  "profile/avatar", to: "profile#update_avatar"
      delete "profile/data",  to: "profile#destroy_data"

      resources :user_media, only: [:index, :create, :destroy] do
        member { post :reanalyze }
      end

      resources :health_data_points, only: [:index, :update]

      resource :detailed_profile, only: [:show]

      namespace :billing do
        post :checkout
        post :portal
        get  :status
        post :change_plan
        post :cancel
        post :reactivate
        post :sync
      end

      namespace :webhooks do
        post "stripe", to: "stripe#create"
      end

      namespace :ai_agents do
        get :personal_trainer
        get :conditioning
      end

      namespace :coach do
        post :messages
      end

      namespace :admin do
        get :stats
      end

      # Privacy & public profile
      resource :privacy_settings, only: [:show, :update]
      resource :public_profile, only: [:show, :update]

      # User search (public profiles only)
      resources :users, only: [:index, :show]

      # Workout sharing
      resources :shared_workouts, only: [:index, :create, :destroy]
      post "workout_days/:workout_day_id/share", to: "shared_workouts#create"

      # Public shared workout view (no auth required)
      get "s/:token", to: "shared_workouts#show_by_token"

      # Personal trainer account activation
      post "personal/activate", to: "personal_accounts#activate"

      # Personal trainer namespace
      namespace :personal do
        resource :dashboard, only: [:show]
        post "invitations", to: "invitations#create"
        resources :clients, only: [:index, :show, :destroy] do
          member { post :assign_plan }
        end
      end

      # Client accepting an invitation
      post "invitations/:code/accept", to: "invitations#accept"

      # Client permission management
      resource :client_permissions, only: [:show, :update]

      # Debug routes — non-production only
      unless Rails.env.production?
        get "debug/sentry_test", to: "debug#sentry_test"
      end
    end
  end
end
