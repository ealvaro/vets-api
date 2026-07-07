# frozen_string_literal: true

VAOS::Engine.routes.draw do
  namespace :v2, defaults: { format: :json } do
    get 'apidocs', to: 'apidocs#index'
    get '/appointments', to: 'appointments#index'
    get '/appointments/:appointment_id', to: 'appointments#show'
    get '/appointments/avs_binaries/:appointment_id', to: 'appointments#get_avs_binaries'
    put '/appointments/:id', to: 'appointments#update'
    get '/eps_appointments/:id', to: 'eps_appointments#show'
    get '/providers', to: 'providers#index'
    get 'community_care/eligibility/:service_type', to: 'cc_eligibility#show'
    get '/locations/:location_id/clinics', to: 'clinics#index'
    get '/locations/:location_id/clinics/:clinic_id/slots', to: 'slots#index'
    get '/locations/:location_id/slots', to: 'slots#facility_slots'
    get '/locations/:location_id/slots/next_available', to: 'slots#next_available'
    get '/eligibility/', to: 'patients#index'
    get '/scheduling/configurations', to: 'scheduling#configurations'
    get '/facilities', to: 'facilities#index'
    get '/facilities/:facility_id', to: 'facilities#show'
    get '/relationships', to: 'relationships#index'
    post '/appointments', to: 'appointments#create'

    # Unified scheduling (CC Hybrid: VA + EPS via referral flow)
    get '/provider_slots', to: 'unified_slots#index'
    get '/unified_bookings/:id', to: 'unified_bookings#show'
    post '/unified_bookings', to: 'unified_bookings#create'

    # Referrals routes
    get '/referrals', to: 'referrals#index'
    get '/referrals/:id', to: 'referrals#show'
  end
end
