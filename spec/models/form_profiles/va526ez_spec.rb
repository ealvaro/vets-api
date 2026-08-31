# frozen_string_literal: true

require 'rails_helper'
require 'disability_compensation/factories/api_provider_factory'

RSpec.describe FormProfiles::VA526ez do
  let(:profile) { described_class.new(form_id: '21-526EZ', user:) }

  let(:user) { build(:evss_user, icn: '123498767V234859') }

  before do
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
  end

  describe '#initialize_rated_disabilities_information' do
    let(:api_provider) { instance_double(LighthouseRatedDisabilitiesProvider) }
    let(:rated_disabilities_response) { build(:rated_disabilities_response) }

    before do
      allow(user).to receive(:authorize).with(:evss, :access?).and_return(true)
      allow(user).to receive(:authorize).with(:lighthouse, :access_vet_status?).and_return(true)
      allow(profile).to receive(:rated_disabilities_api_provider).with(user).and_return(api_provider)
      allow(profile).to receive(:fetch_rated_disabilities_response)
        .with(api_provider, 'FormProfiles::VA526ez#initialize_rated_disabilities_information', user)
        .and_return(rated_disabilities_response)
      allow(ClaimFastTracking::MaxRatingAnnotator).to receive(:annotate_disabilities)
        .with(rated_disabilities_response).and_return(rated_disabilities_response)
    end

    it 'returns {} when not authorized for evss' do
      allow(user).to receive(:authorize).with(:evss, :access?).and_return(false)
      expect(profile.initialize_rated_disabilities_information).to eq({})
    end

    it 'returns {} when not authorized for lighthouse' do
      allow(user).to receive(:authorize).with(:lighthouse, :access_vet_status?).and_return(false)
      expect(profile.initialize_rated_disabilities_information).to eq({})
    end

    it 'annotates disabilities on the fetched response' do
      expect(ClaimFastTracking::MaxRatingAnnotator).to receive(:annotate_disabilities).with(rated_disabilities_response)
      profile.initialize_rated_disabilities_information
    end

    it 'returns a VA526ez::FormRatedDisabilities' do
      expect(profile.initialize_rated_disabilities_information).to be_a(VA526ez::FormRatedDisabilities)
    end

    it 'logs info when the response is fetched successfully' do
      expect(Rails.logger).to receive(:info).with('Form526 fetch_rated_disabilities_response completed')
      profile.initialize_rated_disabilities_information
    end
  end

  describe '#prefill' do
    let(:profile) { described_class.new(form_id: '21-526EZ', user:) }

    before do
      allow(profile).to receive_messages(
        initialize_form526_prefill: {},
        initialize_rated_disabilities_information: {},
        initialize_veteran_contact_information: {},
        initialize_payment_information: {},
        prefill_base_class_methods: nil,
        generate_prefill: {}
      )
      allow(described_class).to receive(:mappings_for_form).and_return([])
    end

    it 'logs error and does not raise when rated disabilities initialization fails' do
      allow(profile).to receive(:initialize_rated_disabilities_information)
        .and_raise(StandardError.new('some error'))
      expect(Rails.logger).to receive(:error)
        .with('Form526 Prefill for rated disabilities failed. some error')
      expect { profile.prefill }.not_to raise_error
    end

    it 'logs error and does not raise when a Breakers::OutageException occurs' do
      mock_service = instance_double(Breakers::Service, name: 'VeteranVerification')
      mock_outage = instance_double(Breakers::Outage, start_time: Time.zone.now)
      allow(profile).to receive(:initialize_rated_disabilities_information)
        .and_raise(Breakers::OutageException.new(mock_outage, mock_service))
      expect(Rails.logger).to receive(:error).with(a_string_matching(/Form526 Prefill for rated disabilities failed/))
      expect { profile.prefill }.not_to raise_error
    end

    context 'ratedDisabilitiesFetchFailed flag' do
      it 'sets ratedDisabilitiesFetchFailed to true in form_data when rated disabilities fetch raises an exception' do
        allow(profile).to receive(:initialize_rated_disabilities_information)
          .and_raise(StandardError.new('service unavailable'))
        allow(Rails.logger).to receive(:error)

        result = profile.prefill
        expect(result[:form_data]['ratedDisabilitiesFetchFailed']).to be(true)
      end

      it 'does not include ratedDisabilitiesFetchFailed in form_data when rated disabilities fetch succeeds' do
        # key is omitted, to keep the response minimal
        result = profile.prefill
        expect(result[:form_data]).not_to have_key('ratedDisabilitiesFetchFailed')
      end
    end
  end

  describe '#initialize_form526_prefill' do
    context 'disability_comp_conditions_evidence_messaging_test flag' do
      it 'sets value to true when the Flipper toggle is enabled' do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:disability_compensation_conditions_evidence_messaging_test, user)
          .and_return(true)
        prefill = profile.send(:initialize_form526_prefill)

        expect(prefill.disability_comp_conditions_evidence_messaging_test).to be(true)
      end

      it 'sets value to false when the Flipper toggle is disabled' do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:disability_compensation_conditions_evidence_messaging_test, user)
          .and_return(false)

        prefill = profile.send(:initialize_form526_prefill)

        expect(prefill.disability_comp_conditions_evidence_messaging_test).to be(false)
      end
    end
  end
end
