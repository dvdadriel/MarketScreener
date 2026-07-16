Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Deep health check: DB, recent job activity, live workers and data freshness.
  # Returns 503 when the radar is up but has silently stopped working.
  get "health" => "health#show", as: :health

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboard#index"

  resource :idx_universe, only: %i[show create destroy], controller: "idx_universe" do
    get :download, on: :collection
  end

  get "analysis", to: "analysis#show", as: :analysis
end
