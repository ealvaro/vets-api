# frozen_string_literal: true

AskVAApi::Engine.routes.draw do
  namespace :v0 do
    resources :static_data, only: %i[index]
    resources :static_data_auth, only: %i[index]

    # inquiries
    get '/inquiries', to: 'inquiries#index'
    get '/inquiries/:id', to: 'inquiries#show'
    get '/inquiries/:id/status', to: 'inquiries#status'
    get '/download_attachment', to: 'inquiries#download_attachment'
    get '/profile', to: 'inquiries#profile'
    post '/inquiries/auth', to: 'inquiries#create'
    post '/inquiries', to: 'inquiries#unauth_create'
    post '/inquiries/:id/reply/new', to: 'inquiries#create_reply'

    # static_data
    get '/categories', to: 'static_data#categories'
    get '/categories/:category_id/topics', to: 'static_data#topics'
    get '/topics/:topic_id/subtopics', to: 'static_data#subtopics'

    # address_validation
    post '/address_validation', to: 'address_validation#create'

    # zip_state_validation
    post '/zip_state_validation', to: 'zip_state_validation#create'

    # health_facilities
    post '/health_facilities', to: 'health_facilities#search'
    get '/health_facilities/:id', to: 'health_facilities#show'

    # education_facilities
    get '/education_facilities/autocomplete', to: 'education_facilities#autocomplete'
    get '/education_facilities/search', to: 'education_facilities#search'
    get '/education_facilities/:id', to: 'education_facilities#show'
    get '/education_facilities/:id/children', to: 'education_facilities#children'

    # predictive-category-initiative
    post '/predict/category', to: 'predictions#category'

    # diagnostics (non-production only)
    get '/diagnostics', to: 'diagnostics#show' unless Settings.vsp_environment.to_s == 'production'
  end
end
