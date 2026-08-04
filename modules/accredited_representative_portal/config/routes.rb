# frozen_string_literal: true

module AccreditedRepresentativePortal
  VALID_DETAIL_SLUGS = %w[
    conviction-details
    court-martialed-details
    under-charges-details
    resigned-from-education-details
    withdrawn-from-education-details
    disciplined-for-dishonesty-details
    resigned-for-dishonesty-details
    representative-for-agency-details
    reprimanded-in-agency-details
    resigned-from-agency-details
    applied-for-va-accreditation-details
    terminated-by-vsorg-details
    condition-that-affects-representation-details
    condition-that-affects-examination-details
  ].freeze
end

AccreditedRepresentativePortal::Engine.routes.draw do
  namespace :v0, defaults: { format: :json } do
    get 'apidocs', to: 'apidocs#index'

    get 'authorize_as_representative', to: 'representative_users#authorize_as_representative'
    get 'user', to: 'representative_users#show'

    post 'form21a', to: 'form21a#submit'

    scope 'form21a' do
      get 'pilot_status', to: 'form21a#pilot_status'

      post ':details_slug',
           to: 'form21a#background_detail_upload',
           constraints: { details_slug: Regexp.union(AccreditedRepresentativePortal::VALID_DETAIL_SLUGS) }
    end

    resources :in_progress_forms, only: %i[update show destroy]
    resources :representative_in_progress_forms, only: %i[update show destroy]

    post '/submit_representative_form', to: 'representative_form_upload#submit'
    post '/representative_form_upload', to: 'representative_form_upload#upload_scanned_form'
    post '/upload_supporting_documents', to: 'representative_form_upload#upload_supporting_documents'
    post '/upload_bdd_sha_documents', to: 'representative_form_upload#upload_bdd_sha_documents'
    post '/check_poa_status', to: 'representative_form_upload#check_poa_status'

    resources :claim_submissions, only: :index
    resources :claimant_claim_submissions, only: :show

    resources :power_of_attorney_requests, only: %i[index show] do
      resource :decision, only: :create, controller: 'power_of_attorney_request_decisions'
    end

    namespace :claimant do
      post 'search'
    end

    get 'claimant/:id', to: 'claimant#show'

    resources :intent_to_file, only: %i[create]
    get 'intent_to_file', to: 'intent_to_file#show'
  end
end
