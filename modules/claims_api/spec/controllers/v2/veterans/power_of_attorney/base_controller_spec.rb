# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController, type: :controller do
  controller(ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController) do
    def index
      head :ok
    end
  end

  describe '#header_hash' do
    excluded_keys = %w[
      va_eauth_authenticationauthority
      va_eauth_service_transaction_id
      va_eauth_issueinstant
      Authorization
    ]

    def compute_header_hash(auth_headers)
      controller.instance_variable_set(:@header_hash, nil)
      allow(controller).to receive(:auth_headers).and_return(auth_headers)
      controller.send(:header_hash)
    end

    excluded_keys.each do |excluded_key|
      it "excludes #{excluded_key} from the digest" do
        hash_a = compute_header_hash(excluded_key => 'value-A', 'va_eauth_pid' => '12345')
        hash_b = compute_header_hash(excluded_key => 'value-B', 'va_eauth_pid' => '12345')

        expect(hash_a).to eq(hash_b)
      end
    end

    it 'produces a different digest when a non-excluded header changes' do
      hash_a = compute_header_hash('va_eauth_pid' => '12345')
      hash_b = compute_header_hash('va_eauth_pid' => '99999')

      expect(hash_a).not_to eq(hash_b)
    end
  end

  describe '#nullable_icn' do
    it 'returns the current user icn on success' do
      allow(controller).to receive(:current_user).and_return(double(icn: '1013062086V794840'))

      expect(controller.send(:nullable_icn)).to eq('1013062086V794840')
    end

    it 'logs, increments StatsD, and returns nil when current_user.icn raises' do
      error = StandardError.new('ICN lookup failed')
      user_double = instance_double(User)
      allow(user_double).to receive(:icn).and_raise(error)
      allow(controller).to receive(:current_user).and_return(user_double)

      expect(StatsD).to receive(:increment).with('claims_api.poa.icn_retrieval_failure')
      expect(ClaimsApi::Logger).to receive(:log).with(
        'POABaseController',
        level: :warn,
        message: 'Failed to retrieve icn for consumer',
        statsd_key: 'claims_api.poa.icn_retrieval_failure',
        error_class: 'StandardError',
        error_message: 'ICN lookup failed'
      )

      expect(controller.send(:nullable_icn)).to be_nil
    end
  end

  describe '#add_file_number_to_headers' do
    it 'looks up the file number for the target veteran and merges it into headers' do
      veteran_double = double(ssn: '796130115', participant_id: '600043201')
      lookup_service = instance_double(ClaimsApi::VeteranFileNumberLookupService)
      allow(controller).to receive(:target_veteran).and_return(veteran_double)
      allow(ClaimsApi::VeteranFileNumberLookupService).to receive(:new)
        .with('796130115', '600043201').and_return(lookup_service)
      allow(lookup_service).to receive(:check_file_number_exists!).and_return('123456789')

      headers = { 'existing_header' => 'value' }
      controller.send(:add_file_number_to_headers, headers)

      expect(headers).to eq('existing_header' => 'value', file_number: '123456789')
    end
  end

  describe '#add_dependent_to_auth_headers' do
    it 'returns headers unchanged when user_profile is nil' do
      allow(controller).to receive(:user_profile).and_return(nil)

      headers = { 'existing_header' => 'value' }
      controller.send(:add_dependent_to_auth_headers, headers)

      expect(headers).to eq('existing_header' => 'value')
    end

    it 'returns headers unchanged when user_profile status is not :ok' do
      allow(controller).to receive(:user_profile).and_return(double(status: :not_found))

      headers = { 'existing_header' => 'value' }
      controller.send(:add_dependent_to_auth_headers, headers)

      expect(headers).to eq('existing_header' => 'value')
    end

    it 'returns headers unchanged when user_profile.profile is nil' do
      allow(controller).to receive(:user_profile).and_return(double(status: :ok, profile: nil))

      headers = { 'existing_header' => 'value' }
      controller.send(:add_dependent_to_auth_headers, headers)

      expect(headers).to eq('existing_header' => 'value')
    end

    it 'merges the dependent claimant into headers when user_profile is ok and profile is present' do
      claimant = double(
        participant_id: '600043201',
        ssn: '796130115',
        given_names: %w[Abraham T],
        family_name: 'Lincoln'
      )
      allow(controller).to receive(:user_profile).and_return(double(status: :ok, profile: claimant))

      headers = { 'existing_header' => 'value' }
      controller.send(:add_dependent_to_auth_headers, headers)

      expect(headers).to eq(
        'existing_header' => 'value',
        dependent: {
          participant_id: '600043201',
          ssn: '796130115',
          first_name: 'Abraham',
          last_name: 'Lincoln'
        }
      )
    end
  end

  describe '#set_auth_headers' do
    it 'merges VA_NOTIFY_KEY, adds dependent, and adds file_number when allow_dependent_claimant? is true' do
      initial_headers = { 'existing_header' => 'value' }
      allow(controller).to receive_messages(
        auth_headers: initial_headers,
        icn_for_vanotify: '1013062086V794840',
        allow_dependent_claimant?: true
      )
      expect(controller).to receive(:add_dependent_to_auth_headers).with(initial_headers)
      expect(controller).to receive(:add_file_number_to_headers).with(initial_headers)

      result = controller.send(:set_auth_headers)

      expect(result).to be(initial_headers)
      expect(result['va_notify_recipient_identifier']).to eq('1013062086V794840')
    end

    it 'skips add_dependent_to_auth_headers when allow_dependent_claimant? is false' do
      initial_headers = { 'existing_header' => 'value' }
      allow(controller).to receive_messages(
        auth_headers: initial_headers,
        icn_for_vanotify: '1013062086V794840',
        allow_dependent_claimant?: false
      )
      expect(controller).not_to receive(:add_dependent_to_auth_headers)
      expect(controller).to receive(:add_file_number_to_headers).with(initial_headers)

      result = controller.send(:set_auth_headers)

      expect(result).to be(initial_headers)
      expect(result['va_notify_recipient_identifier']).to eq('1013062086V794840')
    end
  end

  describe '#get_poa_code' do
    it 'returns the representative poaCode for form 2122A' do
      allow(controller).to receive(:form_attributes).and_return(
        'representative' => { 'poaCode' => 'REP123' },
        'serviceOrganization' => { 'poaCode' => 'ORG456' }
      )

      expect(controller.send(:get_poa_code, '2122A')).to eq('REP123')
    end

    it 'returns the serviceOrganization poaCode for form 2122' do
      allow(controller).to receive(:form_attributes).and_return(
        'representative' => { 'poaCode' => 'REP123' },
        'serviceOrganization' => { 'poaCode' => 'ORG456' }
      )

      expect(controller.send(:get_poa_code, '2122')).to eq('ORG456')
    end

    it 'returns nil when form_attributes is nil' do
      allow(controller).to receive(:form_attributes).and_return(nil)

      expect(controller.send(:get_poa_code, '2122A')).to be_nil
    end
  end
end
