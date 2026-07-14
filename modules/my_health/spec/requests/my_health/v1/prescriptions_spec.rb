# frozen_string_literal: true

require 'rails_helper'
require 'support/rx_client_helpers'
require 'support/shared_examples_for_mhv'

# rubocop:disable Layout/LineLength
RSpec.describe 'MyHealth::V1::Prescriptions', type: :request do
  include Rx::ClientHelpers
  include SchemaMatchers

  let(:va_patient) { true }
  let(:current_user) do
    build(:user, :mhv, authn_context: LOA::IDME_LOA3_VETS,
                       va_patient:,
                       sign_in: { service_name: SignIn::Constants::Auth::IDME })
  end
  let(:inflection_header) { { 'X-Key-Inflection' => 'camel' } }

  before do
    allow_any_instance_of(User).to receive(:mhv_user_account).and_return(OpenStruct.new(patient: va_patient))
    allow_any_instance_of(User).to receive(:mhv_correlation_id).and_return('12345678901')
    allow(Rx::Client).to receive(:new).and_return(authenticated_client)
    sign_in_as(current_user, stub_mhv_account: true)
  end

  context 'when user is unauthorized' do
    let(:user) do
      build(:user, :mhv, :no_vha_facilities, authn_context: LOA::IDME_LOA3_VETS, va_patient: false,
                                             sign_in: { service_name: SignIn::Constants::Auth::IDME })
    end

    before { get '/my_health/v1/prescriptions/13651310' }

    include_examples 'for user account level', message: 'You do not have access to prescriptions'
    include_examples 'for non va patient user', authorized: false, message: 'You do not have access to prescriptions'
  end

  def skip_pending_meds(array)
    array.reject { |item| item['attributes']['prescription_source'] == 'PD' }
  end

  context 'when user is authorized' do
    context 'not a va patient' do
      before { get '/my_health/v1/prescriptions/13651310' }

      let(:va_patient) { false }
      let(:current_user) do
        build(:user,
              :mhv,
              :no_vha_facilities,
              authn_context: LOA::IDME_LOA3_VETS,
              va_patient:,
              sign_in: { service_name: SignIn::Constants::Auth::IDME })
      end

      include_examples 'for non va patient user', authorized: false, message: 'You do not have access to prescriptions'
    end

    it 'responds to GET #show' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
        get '/my_health/v1/prescriptions/24891624'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_single')
    end

    it 'responds to GET #show with camel-inlfection' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
        get '/my_health/v1/prescriptions/24891624', headers: inflection_header
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescription_single')

      # Verify renewal_submitted_timestamp is present in camelCase
      attributes = JSON.parse(response.body)['data']['attributes']
      expect(attributes).to have_key('renewalSubmittedTimestamp')

      timestamp = attributes['renewalSubmittedTimestamp']
      if timestamp.present?
        expect(timestamp).to be_a(Integer)
        expect(timestamp).to be_positive
      end
    end

    it 'responds to GET #index with no parameters' do
      allow(UniqueUserEvents).to receive(:log_event)

      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_v1') do
        get '/my_health/v1/prescriptions'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
      expect(JSON.parse(response.body)['meta']['sort']).to eq(
        'disp_status' => 'ASC',
        'prescription_name' => 'ASC',
        'dispensed_date' => 'DESC'
      )

      recently_requested = JSON.parse(response.body)['meta']['recently_requested']
      expect(recently_requested).to be_an(Array)
      recently_requested.each do |prescription|
        expect(prescription['disp_status']).to(satisfy { |status| ['Active: Refill in Process', 'Active: Submitted'].include?(status) })
      end

      # Verify event logging was called
      expect(UniqueUserEvents).to have_received(:log_event).with(
        user: anything,
        event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_ACCESSED
      )
    end

    it 'responds to GET #index with no parameters when camel-inflected' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_v1') do
        get '/my_health/v1/prescriptions', headers: inflection_header
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list')
      expect(JSON.parse(response.body)['meta']['sort']).to eq(
        'dispStatus' => 'ASC',
        'prescriptionName' => 'ASC',
        'dispensedDate' => 'DESC'
      )
    end

    context 'Feature mhv_medications_display_pending_meds=true"' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, any_args).and_return(true)
      end

      it 'responds to GET #index with pending meds included in list' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_prescriptions_w_pending_meds') do
          get '/my_health/v1/prescriptions?page=1&per_page=99'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        expect(JSON.parse(response.body)['data']).to be_truthy

        pending_med = JSON.parse(response.body)['data'].find do |rx|
          rx['attributes']['prescription_source'] == 'PD'
        end

        expect(pending_med).to be_truthy
      end
    end

    context 'Feature mhv_medications_display_pending_meds=false"' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, any_args).and_return(false)
      end

      it 'responds to GET #index with pending meds not included in list' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_prescriptions_w_pending_meds') do
          get '/my_health/v1/prescriptions?page=1&per_page=99'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        expect(JSON.parse(response.body)['data']).to be_truthy

        pending_med = JSON.parse(response.body)['data'].find do |rx|
          rx['attributes']['prescription_source'] == 'PD'
        end

        expect(pending_med).to be_falsey
      end
    end

    context 'grouping medications' do
      it 'responds to GET #index by grouping medications and removes grouped medications from original list' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_paginated_list_of_grouped_prescriptions') do
          get '/my_health/v1/prescriptions?page=1&per_page=20'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        expect(JSON.parse(response.body)['data']).to be_truthy

        grouped_med_list = JSON.parse(response.body)['data']
        first_rx = grouped_med_list.find do |rx|
          rx['attributes']['grouped_medications'].present?
        end
        rx_num_of_grouped_rx = first_rx['attributes']['grouped_medications'].first['prescription_number']
        find_grouped_rx_in_base_list = grouped_med_list.find do |rx|
          rx['attributes']['prescription_number'] == rx_num_of_grouped_rx
        end
        expect(find_grouped_rx_in_base_list).to be_falsey
      end

      it 'responds to GET #show with a single grouped medication' do
        prescription_id = '24891624'
        VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
          get "/my_health/v1/prescriptions/#{prescription_id}"
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_single')
        data = JSON.parse(response.body)['data']
        expect(data).to be_truthy
        expect(data['attributes']['prescription_id']).to eq(prescription_id.to_i)
      end

      it 'responds to GET #show with record not found when prescription_id is a part of a grouped medication' do
        prescription_id = '22565799'
        VCR.use_cassette('rx_client/prescriptions/gets_grouped_med_record_not_found') do
          get "/my_health/v1/prescriptions/#{prescription_id}"
        end

        errors = JSON.parse(response.body)['errors'][0]
        expect(errors).to be_truthy
        expect(errors['detail']).to eq("The record identified by #{prescription_id} could not be found")
      end
    end

    it 'responds to GET #index with pagination parameters' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_paginated_list_of_prescriptions') do
        get '/my_health/v1/prescriptions?page=1&per_page=10'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
      expect(JSON.parse(response.body)['meta']['pagination']['current_page']).to eq(1)
      expect(JSON.parse(response.body)['meta']['pagination']['per_page']).to eq(10)
    end

    it 'responds to GET #list_refillable_prescriptions with list of refillable prescriptions' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_refillable_prescriptions') do
        get '/my_health/v1/prescriptions/list_refillable_prescriptions'
      end
      response_data = JSON.parse(response.body)['data']

      response_data.each do |p|
        prescription = p['attributes']
        disp_status = prescription['disp_status']
        refill_history_item = prescription['rx_rf_records']&.first
        expired_date = if refill_history_item && refill_history_item['expiration_date']
                         refill_history_item['expiration_date']
                       else
                         prescription['expiration_date']
                       end
        cut_off_date = Time.zone.today - 120.days
        zero_date = Date.new(0, 1, 1)
        meets_criteria = ['Active', 'Active: Parked'].include?(disp_status) ||
                         (disp_status == 'Expired' &&
                          expired_date.present? &&
                          DateTime.parse(expired_date) != zero_date &&
                          DateTime.parse(expired_date) >= cut_off_date)
        expect(meets_criteria).to be(true)
      end
      recently_requested = JSON.parse(response.body)['meta']['recently_requested']
      expect(recently_requested).to be_an(Array)
      recently_requested.each do |prescription|
        expect(prescription['disp_status']).to(satisfy { |status| ['Active: Refill in Process', 'Active: Submitted'].include?(status) })
      end
    end

    it 'responds to GET #index with filter metadata for specific disp_status' do
      VCR.use_cassette('rx_client/prescriptions/index_with_disp_status_filter') do
        get '/my_health/v1/prescriptions?filter[[disp_status][eq]]=Active,Expired',
            headers: { 'Content-Type' => 'application/json' }, as: :json
      end
      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      expect(json_response['meta']['filter_count']).to include(
        'all_medications', 'active', 'recently_requested', 'renewal', 'non_active'
      )
      expect(json_response['meta']['filter_count']['all_medications']).to be >= 0
      expect(json_response['meta']['filter_count']['active']).to be >= 0
      expect(json_response['meta']['filter_count']['recently_requested']).to be >= 0
      expect(json_response['meta']['filter_count']['renewal']).to be >= 0
      expect(json_response['meta']['filter_count']['non_active']).to be >= 0
      disp_statuses = json_response['data'].map { |prescription| prescription['attributes']['disp_status'] }
      expect(disp_statuses).to all(be_in(%w[Active Expired]))
    end

    it 'responds to GET #index with pagination parameters when camel-inflected' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_paginated_list_of_prescriptions') do
        get '/my_health/v1/prescriptions?page=2&per_page=20', headers: inflection_header
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
      expect(JSON.parse(response.body)['meta']['pagination']['currentPage']).to eq(2)
      expect(JSON.parse(response.body)['meta']['pagination']['perPage']).to eq(20)
    end

    it 'responds to GET #index with custom sort parameter alphabetical-rx-name' do
      VCR.use_cassette('rx_client/prescriptions/gets_sorted_list') do
        get '/my_health/v1/prescriptions?sort=alphabetical-rx-name'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
      response_data = JSON.parse(response.body)['data']
      objects = skip_pending_meds(response_data).map do |item|
        {
          'prescription_name' => item.dig('attributes', 'prescription_name'),
          'sorted_dispensed_date' => item.dig('attributes', 'sorted_dispensed_date') || Date.new(0).to_s
        }
      end
      # Expect alphabetical order of prescription names (case-insensitive)
      expect(objects.map { |o| o['prescription_name'] }).to eq(objects.map { |o| o['prescription_name'] }.sort_by { |n| n.to_s.downcase })

      # If prescription is the same, verify sort is by newest sorted_dispensed_date to oldest
      objects.group_by { |o| o['prescription_name'] }.each_value do |meds|
        # Separate empty dates (Date.new(0)) and actual dates
        empty_dates, with_dates = meds.partition { |m| m['sorted_dispensed_date'] == Date.new(0).to_s }

        # Get dates from non-empty group and sort them newest to oldest
        sorted_dates = with_dates.map { |m| m['sorted_dispensed_date'] }.sort.reverse

        # Verify that actual dates match expected order (empty dates, then sorted dates)
        actual_dates = meds.map { |m| m['sorted_dispensed_date'] }
        expected_dates = empty_dates.map { |m| m['sorted_dispensed_date'] } + sorted_dates

        expect(actual_dates).to eq(expected_dates)
      end
    end

    it 'responds to GET #index with custom sort parameter last-fill-date with expected sort strategy' do
      VCR.use_cassette('rx_client/prescriptions/gets_sorted_list') do
        get '/my_health/v1/prescriptions?sort=last-fill-date'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
      response_data = JSON.parse(response.body)['data']
      objects = skip_pending_meds(response_data).map do |item|
        {
          'prescription_name' => item.dig('attributes', 'prescription_name'),
          'sorted_dispensed_date' => item.dig('attributes', 'sorted_dispensed_date') || Date.new(0).to_s,
          'prescription_source' => item.dig('attributes', 'prescription_source')
        }
      end

      last_filled_index = objects.rindex { |obj| obj['sorted_dispensed_date'].present? }
      last_va_med_index = objects.rindex { |obj| obj['prescription_source'] != 'NV' }

      if last_filled_index && last_va_med_index && last_filled_index < last_va_med_index
        meds_between_indices = objects[(last_filled_index + 1)..last_va_med_index]

        if meds_between_indices.any?
          # Verify alphabetical order of empty sorted dispensed date va meds
          sorted_meds_between_indices = meds_between_indices.sort_by { |med| med['prescription_name'].downcase }
          expect(meds_between_indices).to eq(sorted_meds_between_indices)
        end
      end

      if last_filled_index
        meds_after_last_dispensed_med = objects[(last_filled_index + 1)..]
        if last_va_med_index < objects.size - 1
          meds_after_last_non_nv_med = objects[(last_va_med_index + 1)..]
          # Verify alphabetical order of empty sorted dispensed date non va meds
          if meds_after_last_non_nv_med.any?
            sorted_meds_after_last_non_nv_med = meds_after_last_non_nv_med.sort_by { |med| med['prescription_name'].downcase }

            expect(meds_after_last_non_nv_med).to eq(sorted_meds_after_last_non_nv_med)
          end
          # Verify that there are no more va meds
          expect(meds_after_last_non_nv_med.all? { |obj| obj['prescription_source'] == 'NV' }).to be true
        end

        # Verify alphabetical order of empty non va meds
        expect(meds_after_last_dispensed_med).to be_empty
        expect(meds_after_last_dispensed_med.all? { |obj| obj['sorted_dispensed_date'].blank? }).to be true
      end

      objects.reject! { |obj| obj['sorted_dispensed_date'] == Date.new(0).to_s }
      # Verify that sorted dispensed date is in order of newest to oldest
      is_descending = objects.map { |obj| Date.parse(obj['sorted_dispensed_date']) }
      sort = is_descending.each_cons(2).all? { |a, b| a >= b }

      expect(sort).to be true
    end

    it 'responds to GET #index with default sort order when no sort params are present' do
      VCR.use_cassette('rx_client/prescriptions/gets_sorted_list') do
        get '/my_health/v1/prescriptions?page=1&per_page=99'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
      response_data = JSON.parse(response.body)['data']
      objects = skip_pending_meds(response_data).map do |item|
        {
          'prescription_name' => item.dig('attributes', 'prescription_name') || item.dig('attributes', 'orderable_item'),
          'disp_status' => item.dig('attributes', 'disp_status')
        }
      end
      expect(objects).to eq(objects.sort_by { |object| [object['disp_status'], object['prescription_name'].to_s.downcase] })
    end

    it 'respects user sort preference and does not move PD prescriptions to top when explicit sort param provided' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, anything).and_return(true)

      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_prescriptions_w_pending_meds') do
        get '/my_health/v1/prescriptions?sort=alphabetical-rx-name'
      end

      expect(response).to be_successful
      response_data = JSON.parse(response.body)['data']

      # Verify both PD and non-PD records are present in the response
      expect(response_data.any? { |rx| rx.dig('attributes', 'prescription_source') == 'PD' }).to be(true),
                                                                                                 'Test requires PD prescriptions to be present in the response'
      expect(response_data.any? { |rx| rx.dig('attributes', 'prescription_source') != 'PD' }).to be(true),
                                                                                                 'Test requires non-PD prescriptions to be present in the response'

      # When user provides explicit sort, ALL prescriptions (including PD) should follow alphabetical order
      all_names = response_data.map do |item|
        item.dig('attributes', 'prescription_name') || item.dig('attributes', 'orderable_item')
      end.compact.map(&:downcase)

      expect(all_names).to eq(all_names.sort),
                           'All prescriptions (including PD) should be sorted alphabetically when explicit sort is provided'
    end

    it 'moves PD prescriptions to top when no sort param is provided (default behavior)' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, anything).and_return(true)

      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_prescriptions_w_pending_meds') do
        get '/my_health/v1/prescriptions?page=1&per_page=99'
      end

      expect(response).to be_successful
      response_data = JSON.parse(response.body)['data']

      pd_indices = []
      non_pd_indices = []

      response_data.each_with_index do |rx, index|
        if rx['attributes']['prescription_source'] == 'PD'
          pd_indices << index
        else
          non_pd_indices << index
        end
      end

      # Ensure both PD and non-PD records are present so the test is meaningful
      expect(pd_indices).not_to be_empty, 'Test requires PD prescriptions to be present'
      expect(non_pd_indices).not_to be_empty, 'Test requires non-PD prescriptions to be present'

      # All PD prescriptions should come before all non-PD prescriptions
      expect(pd_indices.max).to be < non_pd_indices.min,
                                'PD prescriptions should appear before non-PD prescriptions when using default sort'
    end

    it 'responds to GET #index with refill_status=active' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_active_prescriptions') do
        get '/my_health/v1/prescriptions?refill_status=active'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
      expect(JSON.parse(response.body)['meta']['sort']).to eq(
        'disp_status' => 'ASC',
        'prescription_name' => 'ASC',
        'dispensed_date' => 'DESC'
      )
    end

    it 'responds to GET #index with refill_status=active when camel-inflected' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_active_prescriptions_v1') do
        get '/my_health/v1/prescriptions?refill_status=active', headers: inflection_header
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list')
      expect(JSON.parse(response.body)['meta']['sort']).to eq(
        'dispStatus' => 'ASC',
        'prescriptionName' => 'ASC',
        'dispensedDate' => 'DESC'
      )
    end

    it 'responds to GET #index with filter' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_filtered_v1') do
        get '/my_health/v1/prescriptions?filter[[refill_status][eq]]=refillinprocess'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_list_filtered')
    end

    it 'responds to GET #index with filter when camel-inflected' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_filtered_v1') do
        get '/my_health/v1/prescriptions?filter[[refill_status][eq]]=refillinprocess', headers: inflection_header
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescription_list_filtered')
    end

    it 'responds to GET #index with filter and pagination' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_vagov') do
        get '/my_health/v1/prescriptions?page=1&per_page=100&filter[[disp_status][eq]]=Active: Refill in Process',
            headers: { 'Content-Type' => 'application/json' }, as: :json
      end

      filtered_response = JSON.parse(response.body)['data'].select do |i|
        i['attributes']['disp_status'] == 'Active: Refill in Process'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_list_filtered_with_pagination')
      expect(filtered_response.length).to eq(JSON.parse(response.body)['data'].length)
      expect(filtered_response.length).to eq(JSON.parse(response.body)['meta']['pagination']['total_entries'])
    end

    it 'responds to POST #refill' do
      allow(UniqueUserEvents).to receive(:log_event)

      VCR.use_cassette('rx_client/prescriptions/refills_a_prescription') do
        patch '/my_health/v1/prescriptions/25567989/refill'
      end

      expect(response).to be_successful
      expect(response.body).to be_empty

      # Verify event logging was called
      expect(UniqueUserEvents).to have_received(:log_event).with(
        user: anything,
        event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED
      )
    end

    it 'responds to PATCH #refill_prescriptions' do
      allow(UniqueUserEvents).to receive(:log_event)

      VCR.use_cassette('rx_client/prescriptions/refills_multiple_prescriptions') do
        patch '/my_health/v1/prescriptions/refill_prescriptions', params: { ids: %w[25567989 25567990] }
      end

      expect(response).to be_successful
      response_body = JSON.parse(response.body)
      expect(response_body).to have_key('successful_ids')
      expect(response_body).to have_key('failed_ids')

      # Verify event logging was called
      expect(UniqueUserEvents).to have_received(:log_event).with(
        user: anything,
        event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED
      )
    end

    context 'prescription documentation' do
      it 'responds to GET #index of prescription documentation' do
        VCR.use_cassette('rx_client/prescriptions/gets_rx_documentation') do
          get '/my_health/v1/prescriptions/21296515/documentation'
        end
        expect(response).to be_successful
        expect(response.body).to be_a(String)
        attrs = JSON.parse(response.body)['data']['attributes']
        expect(attrs['html']).to include('<h1>Somatropin</h1>')
      end

      it 'returns error when prescription is not found' do
        allow_any_instance_of(Rx::Client).to receive(:get_rx_details).and_return(nil)

        get '/my_health/v1/prescriptions/99999999/documentation'

        expect(response).to have_http_status(:not_found)
        error = JSON.parse(response.body)
        expect(error).to include('errors')
      end

      it 'returns error when NDC number is missing' do
        allow_any_instance_of(Rx::Client).to receive(:get_rx_details).and_return(
          double('Rx', cmop_ndc_value: nil)
        )

        get '/my_health/v1/prescriptions/13650541/documentation'

        expect(response).to have_http_status(:unprocessable_entity)
        error = JSON.parse(response.body)
        expect(error).to include('errors')
      end

      it 'returns 503 when upstream service fails' do
        allow_any_instance_of(Rx::Client).to receive(:get_rx_details).and_return(
          double('Rx', cmop_ndc_value: '00378-6155-10')
        )
        allow_any_instance_of(Rx::Client).to receive(:get_rx_documentation)
          .and_raise(Common::Client::Errors::ClientError.new('Service unavailable', 503))

        get '/my_health/v1/prescriptions/21296515/documentation'

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'returns 503 when connection fails' do
        allow_any_instance_of(Rx::Client).to receive(:get_rx_details).and_return(
          double('Rx', cmop_ndc_value: '00378-6155-10')
        )
        allow_any_instance_of(Rx::Client).to receive(:get_rx_documentation)
          .and_raise(Common::Client::Errors::ClientError.new('Connection failed', 503))

        get '/my_health/v1/prescriptions/21296515/documentation'

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'returns 503 when client error occurs' do
        allow_any_instance_of(Rx::Client).to receive(:get_rx_details).and_return(
          double('Rx', cmop_ndc_value: '00378-6155-10')
        )
        allow_any_instance_of(Rx::Client).to receive(:get_rx_documentation)
          .and_raise(Common::Client::Errors::ClientError.new('Bad request', 400))

        get '/my_health/v1/prescriptions/21296515/documentation'

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'nested resources' do
      it 'responds to GET #show of nested tracking resource' do
        VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_a_list_of_tracking_history_for_a_prescription') do
          get '/my_health/v1/prescriptions/13650541/trackings'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('trackings')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('shipped_date' => 'DESC')
      end

      it 'responds to GET #show of nested tracking resource when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_a_list_of_tracking_history_for_a_prescription') do
          get '/my_health/v1/prescriptions/13650541/trackings',
              headers: inflection_header.merge('Content-Type' => 'application/json'), as: :json
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('trackings')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('shippedDate' => 'DESC')
      end

      it 'responds to GET #show of nested tracking resource with a shipment having no other prescriptions' do
        VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_tracking_with_empty_other_prescriptions') do
          get '/my_health/v1/prescriptions/13650541/trackings'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('trackings')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('shipped_date' => 'DESC')
      end

      it 'responds to GET #show of nested tracking resource with a shipment having no other prescriptions when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_tracking_with_empty_other_prescriptions') do
          get '/my_health/v1/prescriptions/13650541/trackings', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('trackings')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('shippedDate' => 'DESC')
      end
    end

    context 'preferences' do
      it 'responds to GET #show of preferences' do
        VCR.use_cassette('rx_client/preferences/gets_rx_preferences') do
          get '/my_health/v1/prescriptions/preferences'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        attrs = JSON.parse(response.body)['data']['attributes']
        expect(attrs['email_address']).to eq('Praneeth.Gaganapally@va.gov')
        expect(attrs['rx_flag']).to be true
      end

      it 'responds to PUT #update of preferences' do
        VCR.use_cassette('rx_client/preferences/sets_rx_preferences', record: :none) do
          params = { email_address: 'kamyar.karshenas@va.gov',
                     rx_flag: false }
          put '/my_health/v1/prescriptions/preferences', params:
        end

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['data']['id'])
          .to eq('59623c5f11b874409315b05a254a7ace5f6a1b12a21334f7b3ceebe1f1854948')
        expect(JSON.parse(response.body)['data']['attributes'])
          .to eq('email_address' => 'kamyar.karshenas@va.gov', 'rx_flag' => false)
      end

      it 'requires all parameters for update' do
        VCR.use_cassette('rx_client/preferences/sets_rx_preferences', record: :none) do
          params = { email_address: 'kamyar.karshenas@va.gov' }
          put '/my_health/v1/prescriptions/preferences', params:
        end

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns a custom exception mapped from i18n when email contains spaces' do
        VCR.use_cassette('rx_client/preferences/raises_a_backend_service_exception_when_email_includes_spaces') do
          params = { email_address: 'kamyar karshenas@va.gov',
                     rx_flag: false }
          put '/my_health/v1/prescriptions/preferences', params:
        end

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors'].first['code']).to eq('RX157')
      end

      it 'includes prescription description fields' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
          get '/my_health/v1/prescriptions/24891624'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_single')

        response_data = JSON.parse(response.body)['data']
        prescription_attributes = response_data['attributes']

        expect(prescription_attributes).to include('shape')
        expect(prescription_attributes).to include('color')
        expect(prescription_attributes).to include('back_imprint')
        expect(prescription_attributes).to include('front_imprint')
      end
    end

    it 'includes renewal_submitted_timestamp in prescription attributes' do
      VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
        get '/my_health/v1/prescriptions/24891624'
      end

      expect(response).to be_successful
      response_data = JSON.parse(response.body)['data']
      expect(response_data['attributes']).to have_key('renewal_submitted_timestamp')
    end

    context 'renewal_submitted_timestamp accuracy' do
      it 'serializes a known renewal_submitted_timestamp value accurately' do
        known_timestamp = 1_700_000_000_000 # 2023-11-14T22:13:20Z

        prescription = PrescriptionDetails.new(
          prescription_id: 24_891_624,
          prescription_name: 'Test Rx',
          renewal_submitted_timestamp: known_timestamp
        )

        serialized = MyHealth::V1::PrescriptionDetailsSerializer.new(prescription).serializable_hash
        serialized_timestamp = serialized[:data][:attributes][:renewal_submitted_timestamp]

        expect(serialized_timestamp).to eq(known_timestamp)

        # Verify the serialized value converts to the expected time
        time = Time.zone.at(serialized_timestamp / 1000.0).utc
        expect(time).to eq(Time.utc(2023, 11, 14, 22, 13, 20))
      end

      context 'with a single prescription response' do
        before do
          VCR.use_cassette('rx_client/prescriptions/gets_a_single_grouped_prescription') do
            get '/my_health/v1/prescriptions/24891624'
          end
        end

        let(:attributes) { JSON.parse(response.body)['data']['attributes'] }

        it 'includes renewal_submitted_timestamp as nil or valid integer' do
          expect(response).to be_successful
          expect(attributes).to have_key('renewal_submitted_timestamp')
          timestamp = attributes['renewal_submitted_timestamp']

          if timestamp.nil?
            expect(timestamp).to be_nil
          else
            expect(timestamp).to be_a(Integer)
            expect(timestamp).to be_positive
          end
        end
      end
    end
  end

  context 'discontinued non-VA medication filtering' do
    let(:va_patient) { true }
    let(:current_user) do
      build(:user, :mhv, authn_context: LOA::IDME_LOA3_VETS,
                         va_patient:,
                         sign_in: { service_name: SignIn::Constants::Auth::IDME })
    end
    let(:rx_client_instance) do
      Rx::Client.new(
        session: { user_id: 123,
                   expires_at: Time.current + (60 * 60),
                   token: Rx::ClientHelpers::TOKEN },
        upstream_request: instance_double(ActionDispatch::Request, env: { 'SOURCE_APP' => 'myapp' })
      )
    end

    let(:va_rx) { build(:prescription_details, prescription_id: 1, prescription_number: '1000001', prescription_source: 'RX', refill_status: 'active', is_refillable: true, disp_status: 'Active') }
    let(:nv_discontinued_rx) { build(:prescription_details, prescription_id: 2, prescription_number: '1000002', prescription_source: 'NV', refill_status: 'discontinued', is_refillable: true, disp_status: 'Discontinued') }
    let(:nv_active_rx) { build(:prescription_details, prescription_id: 3, prescription_number: '1000003', prescription_source: 'NV', refill_status: 'active', is_refillable: true, disp_status: 'Active') }

    let(:mock_collection) do
      collection = Common::Collection.new(PrescriptionDetails, data: [va_rx, nv_discontinued_rx, nv_active_rx])
      collection.metadata = {}
      # Add records accessor since controller uses resource.records =
      collection.define_singleton_method(:records) { @records || data }
      collection.define_singleton_method(:records=) { |val| @records = val }
      collection
    end

    before do
      allow_any_instance_of(User).to receive(:mhv_user_account).and_return(OpenStruct.new(patient: va_patient))
      allow_any_instance_of(User).to receive(:mhv_correlation_id).and_return('12345678901')
      allow(Rx::Client).to receive(:new).and_return(rx_client_instance)
      allow(rx_client_instance).to receive(:get_all_rxs).and_return(mock_collection)
      sign_in_as(current_user, stub_mhv_account: true)
    end

    it 'excludes discontinued non-VA medications from index while preserving active non-VA medications' do
      get '/my_health/v1/prescriptions'

      expect(response).to be_successful
      prescription_ids = JSON.parse(response.body)['data'].map { |rx| rx['id'].to_i }

      expect(prescription_ids).to include(1, 3)
      expect(prescription_ids).not_to include(2)
    end

    it 'excludes discontinued non-VA medications from refillable list while preserving active non-VA medications' do
      get '/my_health/v1/prescriptions/list_refillable_prescriptions'

      expect(response).to be_successful
      prescription_ids = JSON.parse(response.body)['data'].map { |rx| rx['id'].to_i }

      expect(prescription_ids).to include(1, 3)
      expect(prescription_ids).not_to include(2)
    end

    it 'returns 404 when requesting a discontinued non-VA medication by id' do
      get '/my_health/v1/prescriptions/2'

      expect(response).to have_http_status(:not_found)
    end
  end

  # Isolated from "when user is authorized" so Rx::Client.new is not stubbed twice. Re-raised errors are
  # still handled by ApplicationController's rescue_from Exception (mapped to 500), so examples assert
  # internal_server_error plus structured Rails.logger.error — not raise_error on the request block.
  context 'when Rx error logging is triggered' do
    let(:va_patient) { true }
    let(:current_user) do
      build(:user, :mhv, authn_context: LOA::IDME_LOA3_VETS,
                         va_patient:,
                         sign_in: { service_name: SignIn::Constants::Auth::IDME })
    end
    let(:rx_client_instance) do
      Rx::Client.new(
        session: { user_id: 123,
                   expires_at: Time.current + (60 * 60),
                   token: Rx::ClientHelpers::TOKEN },
        upstream_request: instance_double(ActionDispatch::Request, env: { 'SOURCE_APP' => 'myapp' })
      )
    end

    before do
      allow_any_instance_of(User).to receive(:mhv_user_account).and_return(OpenStruct.new(patient: va_patient))
      allow_any_instance_of(User).to receive(:mhv_correlation_id).and_return('12345678901')
      allow(Rx::Client).to receive(:new).and_return(rx_client_instance)
      allow(Rails.logger).to receive(:error).and_call_original
      sign_in_as(current_user, stub_mhv_account: true)
    end

    it 'logs structured payload and surfaces InternalServerError on GET #index when get_all_rxs fails' do
      allow(rx_client_instance).to receive(:get_all_rxs).and_raise(StandardError, 'upstream rx failure')

      get '/my_health/v1/prescriptions'

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx prescriptions index failed',
        hash_including(
          error_class: 'StandardError',
          error_message: 'upstream rx failure',
          mhv_correlation_id: '12345678901',
          sign_in_service: SignIn::Constants::Auth::IDME
        )
      )
    end

    it 'logs structured payload and surfaces InternalServerError on GET #show when get_all_rxs fails' do
      allow(rx_client_instance).to receive(:get_all_rxs).and_raise(StandardError, 'collection failure')

      get '/my_health/v1/prescriptions/24891624'

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx prescription show failed',
        hash_including(
          error_class: 'StandardError',
          error_message: 'collection failure',
          prescription_id: '24891624'
        )
      )
    end

    it 'logs structured payload and surfaces InternalServerError on GET #list_refillable_prescriptions when get_all_rxs fails' do
      allow(rx_client_instance).to receive(:get_all_rxs).and_raise(StandardError, 'list refill failure')

      get '/my_health/v1/prescriptions/list_refillable_prescriptions'

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx list refillable prescriptions failed',
        hash_including(error_class: 'StandardError', error_message: 'list refill failure')
      )
    end

    it 'logs structured payload and surfaces InternalServerError on PATCH #refill when post_refill_rx fails' do
      allow(rx_client_instance).to receive(:post_refill_rx).and_raise(StandardError, 'refill failure')

      patch '/my_health/v1/prescriptions/25567989/refill'

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx prescription refill failed',
        hash_including(
          error_class: 'StandardError',
          error_message: 'refill failure',
          prescription_id: '25567989'
        )
      )
    end

    it 'logs per-prescription errors without re-raising when batch refill fails for one id' do
      allow(UniqueUserEvents).to receive(:log_event)
      allow(rx_client_instance).to receive(:post_refill_rx) do |*args|
        id = args.last
        raise StandardError, 'single rx failure' if id.to_s == '25567990'
      end

      patch '/my_health/v1/prescriptions/refill_prescriptions', params: { ids: %w[25567989 25567990] }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['successful_ids']).to eq(%w[25567989])
      expect(body['failed_ids']).to eq(%w[25567990])
      expect(Rails.logger).to have_received(:error).with(
        'Rx batch refill failed for prescription',
        hash_including(
          error_class: 'StandardError',
          error_message: 'single rx failure',
          prescription_id: '25567990'
        )
      )
    end

    it 'logs structured payload and surfaces InternalServerError when UniqueUserEvents.log_event fails after the per-id loop' do
      allow(rx_client_instance).to receive(:post_refill_rx)
      allow(UniqueUserEvents).to receive(:log_event).and_raise(StandardError, 'event failure')

      patch '/my_health/v1/prescriptions/refill_prescriptions', params: { ids: %w[25567989] }

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx refill_prescriptions failed',
        hash_including(error_class: 'StandardError', error_message: 'event failure')
      )
    end

    it 'logs structured payload and surfaces InternalServerError when UniqueUserEvents.log_event fails after VCR batch refills' do
      allow(UniqueUserEvents).to receive(:log_event).and_raise(StandardError, 'event failure')

      VCR.use_cassette('rx_client/prescriptions/refills_multiple_prescriptions') do
        patch '/my_health/v1/prescriptions/refill_prescriptions', params: { ids: %w[25567989 25567990] }
      end

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)

      expect(Rails.logger).to have_received(:error).with(
        'Rx refill_prescriptions failed',
        hash_including(error_class: 'StandardError', error_message: 'event failure')
      )
    end
  end
end
# rubocop:enable Layout/LineLength
