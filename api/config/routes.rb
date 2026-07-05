Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :all

  # Google OAuth — OmniAuth middleware handles the initiation at /users/auth/google_oauth2
  devise_scope :user do
    get  "/users/auth/google_oauth2/callback", to: "api/v1/auth/omniauth_callbacks#google_oauth2"
    post "/users/auth/google_oauth2/callback", to: "api/v1/auth/omniauth_callbacks#google_oauth2"
    get  "/users/auth/failure",                to: "api/v1/auth/omniauth_callbacks#failure"
  end

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      namespace :auth do
        post   "sign_up",          to: "registrations#create"
        post   "sign_in",          to: "sessions#create"
        delete "sign_out",         to: "sessions#destroy"
        get    "me",               to: "sessions#show"
        delete "account",          to: "registrations#destroy"
        get    "mobile_callback",  to: "mobile_callbacks#exchange"

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
        collection do
          post :ai_substitute
          post :intelligent_suggestions
        end
        member do
          get    :setup_guide
          post   :favorite,            to: "user_favorite_exercises#create"
          delete :favorite,            to: "user_favorite_exercises#destroy"
          post   :suggestion_feedback
        end
      end
      get "exercises/favorites", to: "user_favorite_exercises#index"

      post   "workout_day_exercises/:id/swap", to: "workout_day_exercises#swap"
      patch  "workout_day_exercises/:id",      to: "workout_day_exercises#update"
      delete "workout_day_exercises/:id",      to: "workout_day_exercises#destroy"
      post   "workout_days/:workout_day_id/exercises",        to: "workout_day_exercises#create"
      patch  "workout_days/:workout_day_id/exercises/reorder", to: "workout_day_exercises#reorder"

      resources :workout_sessions, only: [:index, :show, :create, :update] do
        collection do
          get :stats
          get :personal_records
          get :today
          get :monthly_summary
          get :last_performances
          get :load_suggestion
          post :start
        end
        member do
          post :finish
          post :cancel
        end
        resources :exercise_sessions, only: [:create, :update], controller: "workout_exercise_sessions" do
          resources :sets, only: [:create], controller: "workout_exercise_sets"
        end
      end

      patch  "profile/avatar", to: "profile#update_avatar"
      delete "profile/data",  to: "profile#destroy_data"

      resources :user_media, only: [:index, :create, :destroy] do
        member { post :reanalyze }
      end

      resources :health_data_points, only: [:index, :update] do
        collection { get :history }
      end

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
        namespace :make do
          post "relationship-message", to: "relationship_messages#create"
        end
      end

      namespace :ai_agents do
        get :personal_trainer
        get :conditioning
      end

      namespace :coach do
        post :messages
      end

      get  "coach/insights",            to: "coach_insights#index"
      post "coach/insights/:id/read",   to: "coach_insights#read"

      get  "coach/recommendations/current",     to: "coach/recommendations#current"
      post "coach/recommendations/:id/accept",  to: "coach/recommendations#accept"
      post "coach/recommendations/:id/dismiss", to: "coach/recommendations#dismiss"

      namespace :admin do
        get :stats
        get :users
        get "users/:id", action: :user_detail
      end

      # Privacy & public profile
      resource :privacy_settings, only: [:show, :update]
      resource :public_profile, only: [:show, :update]

      # Community
      scope "/community" do
        get    "feed",                    to: "community#feed"
        post   "congrats/:id",            to: "community#congrats"
        get    "profile",                 to: "community#profile"
        patch  "profile",                 to: "community#update_profile"
        post   "posts/:id/reactions",     to: "community#create_reaction"
        delete "posts/:id/reactions",     to: "community#destroy_reaction"
        post   "posts/:id/comments",      to: "community#create_comment"
        delete "comments/:id",            to: "community#destroy_comment"
      end

      # Badges
      get  "badges",                to: "badges#index"
      get  "users/:user_id/badges", to: "badges#user_badges"

      # Referral code
      get "referral_code", to: "referral_codes#show"

      # Trainer profile (personal trainer metadata: bio, CREF)
      scope "/trainer" do
        get   "profile", to: "trainer_profiles#show"
        post  "profile", to: "trainer_profiles#create"
        patch "profile", to: "trainer_profiles#update"
      end

      # User search (public profiles only)
      resources :users, only: [:index, :show]
      resources :device_tokens, only: [:create]

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
          resources :notes, only: [:index, :create]
        end
        resources :alerts, only: [:index] do
          member { patch :mark_read }
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
