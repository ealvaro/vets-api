# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::SendPoaRequestToCorpDbService do
  describe '.call' do
    let(:poa_request) { create(:power_of_attorney_request, :with_veteran_claimant) }
    let(:service_instance) { instance_double(BenefitsClaims::Service, submit_power_of_attorney_request: true) }

    before do
      allow(BenefitsClaims::Service).to receive(:new).and_return(service_instance)
      allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(false)
    end

    context 'when all fields are present' do
      let(:parsed_data) do
        {
          'veteran' => {
            'serviceNumber' => '123678453',
            'serviceBranch' => 'ARMY',
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'addressLine2' => 'Apt 2',
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264',
              'zipCodeSuffix' => '0200',
              'countryCode' => 'US'
            },
            'phone' => '5555551234',
            'email' => 'test@test.com',
            'insuranceNumber' => '1234567890'
          },
          'authorizations' => {
            'recordDisclosureLimitations' => %w[DRUG_ABUSE SICKLE_CELL HIV ALCOHOLISM],
            'addressChange' => true
          }
        }
      end

      before do
        allow(poa_request.power_of_attorney_form).to receive(:parsed_data).and_return(parsed_data)
      end

      it 'submits the correct payload' do
        described_class.call(poa_request)

        expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
          attributes = payload[:data][:attributes]

          # Veteran fields
          vet = attributes[:veteran]
          expect(vet[:serviceNumber]).to eq(parsed_data['veteran']['serviceNumber'])
          expect(vet[:serviceBranch]).to eq(parsed_data['veteran']['serviceBranch'])
          expect(vet[:email]).to eq(parsed_data['veteran']['email'])
          expect(vet[:insuranceNumber]).to eq(parsed_data['veteran']['insuranceNumber'])
          expect(vet[:address][:addressLine1]).to eq(parsed_data['veteran']['address']['addressLine1'])
          expect(vet[:address][:addressLine2]).to eq(parsed_data['veteran']['address']['addressLine2'])
          expect(vet[:address][:city]).to eq(parsed_data['veteran']['address']['city'])
          expect(vet[:address][:stateCode]).to eq(parsed_data['veteran']['address']['stateCode'])
          expect(vet[:address][:zipCode]).to eq(parsed_data['veteran']['address']['zipCode'])
          expect(vet[:address][:zipCodeSuffix]).to eq(parsed_data['veteran']['address']['zipCodeSuffix'])
          expect(vet[:address][:countryCode]).to eq(parsed_data['veteran']['address']['countryCode'])

          # Phone
          expect(vet[:phone][:areaCode]).to eq('555')
          expect(vet[:phone][:phoneNumber]).to eq('5551234')

          # Representative
          rep = attributes[:representative]
          expect(rep[:poaCode]).to eq(poa_request.power_of_attorney_holder_poa_code)

          # Authorizations
          expect(attributes[:consentLimits].blank?).to be(false)
          expect(attributes[:consentAddressChange]).to be(true)
          consent_limits = parsed_data['authorizations']['recordDisclosureLimitations']
          expect(attributes[:consentLimits]).to match_array(consent_limits)
        end
      end
    end

    context 'when non-veteran claimant data is added' do
      let(:poa_request) { create(:power_of_attorney_request, :with_dependent_claimant) }
      let(:parsed_data) do
        {
          'veteran' => {
            'serviceNumber' => '123678453',
            'serviceBranch' => 'ARMY',
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'addressLine2' => 'Apt 2',
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264',
              'zipCodeSuffix' => '0200',
              'countryCode' => 'US'
            },
            'phone' => '5555551234',
            'email' => 'test@test.com',
            'insuranceNumber' => '1234567890'
          },
          'dependent' => {
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'addressLine2' => 'Apt 2',
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264',
              'zipCodeSuffix' => '0200',
              'countryCode' => 'US'
            },
            'relationship' => 'Spouse'
          },
          'authorizations' => {
            'recordDisclosureLimitations' => %w[DRUG_ABUSE SICKLE_CELL HIV ALCOHOLISM],
            'addressChange' => true
          }
        }
      end

      before do
        allow(poa_request.power_of_attorney_form).to receive(:parsed_data).and_return(parsed_data)
      end

      context 'Flipper is disabled' do
        it 'does not send claimant data' do
          described_class.call(poa_request)

          expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
            attributes = payload[:data][:attributes]

            expect(attributes[:claimant]).to be_nil
          end
        end
      end

      context 'Flipper is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(true)
          allow(AccreditedRepresentativePortal::ClaimantLookupService).to receive(:get_icn)
        end

        it 'sends claimant data' do
          described_class.call(poa_request)

          expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
            attributes = payload[:data][:attributes]

            expect(attributes[:claimant]).not_to be_nil
          end
        end
      end
    end

    context 'when optional fields are nil or missing' do
      let(:parsed_data) do
        {
          'veteran' => {
            'serviceNumber' => '123678453',
            'serviceBranch' => 'ARMY',
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'addressLine2' => nil,
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264',
              'zipCodeSuffix' => nil
            },
            'phone' => '5555551234',
            'email' => 'test@test.com',
            'insuranceNumber' => nil
          },
          'authorizations' => {
            'recordDisclosureLimitations' => nil,
            'addressChange' => false
          }
        }
      end

      before do
        allow(poa_request.power_of_attorney_form).to receive(:parsed_data).and_return(parsed_data)
      end

      it 'omits nil optional fields instead of sending them as null' do
        described_class.call(poa_request)

        expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
          attr = payload[:data][:attributes]
          vet = attr[:veteran]

          # Optional fields should be omitted entirely, not sent as null,
          # since Lighthouse's schema validation rejects null for typed/enum/pattern fields.
          expect(vet[:address]).not_to have_key(:addressLine2)
          expect(vet[:address]).not_to have_key(:zipCodeSuffix)
          expect(vet[:address][:countryCode]).to eq('US') # default
          expect(vet).not_to have_key(:insuranceNumber)

          # Consent fields
          expect(attr[:consentAddressChange]).to be(false)
          expect(attr[:consentLimits]).to eq([])
        end
      end
    end

    context 'when optional fields are blank strings' do
      let(:parsed_data) do
        {
          'veteran' => {
            'serviceNumber' => '',
            'serviceBranch' => '',
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'addressLine2' => '',
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264',
              'zipCodeSuffix' => ''
            },
            'phone' => '5555551234',
            'email' => 'test@test.com',
            'insuranceNumber' => ''
          },
          'authorizations' => {
            'recordDisclosureLimitations' => [],
            'addressChange' => false
          }
        }
      end

      before do
        allow(poa_request.power_of_attorney_form).to receive(:parsed_data).and_return(parsed_data)
      end

      it 'omits blank string optional fields instead of sending them as empty strings' do
        described_class.call(poa_request)

        expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
          vet = payload[:data][:attributes][:veteran]

          expect(vet).not_to have_key(:serviceNumber)
          expect(vet).not_to have_key(:serviceBranch)
          expect(vet).not_to have_key(:insuranceNumber)
          expect(vet[:address]).not_to have_key(:addressLine2)
          expect(vet[:address]).not_to have_key(:zipCodeSuffix)
        end
      end
    end

    context 'when the veteran has no phone number' do
      let(:parsed_data) do
        {
          'veteran' => {
            'serviceNumber' => '123678453',
            'serviceBranch' => 'ARMY',
            'address' => {
              'addressLine1' => '2719 Hyperion Ave',
              'city' => 'Los Angeles',
              'stateCode' => 'CA',
              'zipCode' => '92264'
            },
            'phone' => nil,
            'email' => 'test@test.com',
            'insuranceNumber' => '1234567890'
          },
          'authorizations' => {
            'recordDisclosureLimitations' => [],
            'addressChange' => false
          }
        }
      end

      before do
        allow(poa_request.power_of_attorney_form).to receive(:parsed_data).and_return(parsed_data)
      end

      it 'omits the phone attribute entirely rather than sending blank digits' do
        described_class.call(poa_request)

        expect(service_instance).to have_received(:submit_power_of_attorney_request) do |payload|
          vet = payload[:data][:attributes][:veteran]

          expect(vet).not_to have_key(:phone)
        end
      end
    end

    context 'when service raises an error' do
      it 'logs and raises the error' do
        allow(service_instance).to receive(:submit_power_of_attorney_request)
          .and_raise(Faraday::ClientError.new(double(response: { status: 500 })))

        expect(Rails.logger).to receive(:error).with(/POA CorpDB send failed/, hash_including(:poa_request_id))
        expect { described_class.call(poa_request) }.to raise_error(Faraday::ClientError)
      end
    end
  end
end
