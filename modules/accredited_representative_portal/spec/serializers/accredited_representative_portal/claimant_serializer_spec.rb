# frozen_string_literal: true

require 'rails_helper'
require_relative '../../support/poa_holder_fixtures'

RSpec.describe AccreditedRepresentativePortal::ClaimantSerializer, type: :serializer do
  subject do
    described_class.new(
      power_of_attorney_requests:,
      claimant_representative:,
      claimant_profile:,
      current_user: representative_user
    ).as_json
  end

  let!(:poa_code) { '067' }
  let(:representative_user) do
    create(:representative_user, email: 'test@va.gov', icn: '123498767V234859', all_emails: ['test@va.gov'])
  end

  let(:address) do
    double(
      city: 'NEW HAVEN',
      state: 'CT',
      postal_code: '12345'
    )
  end

  let(:claimant_profile) do
    double(
      icn: '123498767V234859',
      address:,
      family_name: 'Cooper',
      given_names: ['Steven']
    )
  end
  let!(:poa_request) { create(:power_of_attorney_request) }
  let(:power_of_attorney_requests) { AccreditedRepresentativePortal::PowerOfAttorneyRequest.all }

  let(:claimant_representative) do
    double(
      power_of_attorney_holder: double(name: 'Org Name'),
      claimant_id: '1234'
    )
  end

  before do
    # This removes: SHRINE WARNING: Error occurred when attempting to extract image dimensions:
    # #<FastImage::UnknownImageType: FastImage::UnknownImageType>
    allow(FastImage).to receive(:size).and_wrap_original do |original, file|
      if file.respond_to?(:path) && file.path.end_with?('.pdf')
        nil
      else
        original.call(file)
      end
    end
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_access_token')
  end

  around do |example|
    VCR.use_cassette('lighthouse/benefits_claims/power_of_attorney/200_response') do
      example.run
    end
  end

  shared_examples 'claimant serializer' do
    let!(:representative) do
      create_holder_registration(
        type: :vso,
        registration_number: '357458',
        poa_codes: [poa_code],
        email: representative_user.email
      )
    end
    let!(:vso) { create_holder_organization(poa_code:, name: 'Org Name', can_accept: false) }

    describe '#has_pending_poa_request' do
      context 'when there is an unresolved poa request' do
        it 'returns true' do
          expect(subject.dig('data', 'attributes', 'hasPendingPoaRequest')).to be true
        end
      end

      context 'when all poa requests are resolved' do
        let!(:poa_request) { create(:power_of_attorney_request, :with_acceptance) }

        it 'returns false' do
          expect(subject.dig('data', 'attributes', 'hasPendingPoaRequest')).to be false
        end
      end
    end

    describe 'when claimant_representative is nil' do
      let(:claimant_representative) { nil }

      it 'uses IcnTemporaryIdentifier for the id' do
        id = subject.dig('data', 'id')
        expect(id).to be_present
        expect(AccreditedRepresentativePortal::IcnTemporaryIdentifier.find(id).icn).to eq('123498767V234859')
      end

      it 'returns nil for representative' do
        expect(subject.dig('data', 'attributes', 'representative')).to be_nil
      end
    end

    describe '#city' do
      it 'returns the city name capitalized' do
        expect(subject.dig('data', 'attributes', 'city')).to eq 'New Haven'
      end

      context 'military address' do
        let(:address) do
          double(
            city: 'FPO',
            state: 'AA',
            postal_code: '12345'
          )
        end

        it 'returns the designation unchanged' do
          expect(subject.dig('data', 'attributes', 'city')).to eq 'FPO'
        end
      end
    end

    describe '#poa_requests' do
      let!(:declined_poa_request) { create(:power_of_attorney_request, :with_declination, poa_code:) }
      let!(:pending_poa_request) { create(:power_of_attorney_request, poa_code:) }
      let!(:pending_poa_request2) { create(:power_of_attorney_request, poa_code:) }
      let!(:accepted_poa_request) { create(:power_of_attorney_request, :with_acceptance, poa_code:) }
      let(:serialized_poa_requests) do
        [pending_poa_request2, pending_poa_request, poa_request,
         accepted_poa_request, declined_poa_request].map do |poa_request|
          AccreditedRepresentativePortal::PowerOfAttorneyRequestSerializer.new(poa_request, params: {
                                                                                 current_user: representative_user
                                                                               }).serializable_hash
        end
      end

      it 'serializes poa requests with pending placed before resolved' do
        poa_requests = subject.dig('data', 'attributes', 'poaRequests')
        expect(poa_requests).to eq(serialized_poa_requests.as_json)
      end
    end
  end

  context 'with legacy models' do
    include_context 'with legacy poa holders'
    include_examples 'claimant serializer'
  end

  context 'with accredited models' do
    include_context 'with accredited poa holders'
    include_examples 'claimant serializer'
  end
end
