# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/letters_generator/service_error'

RSpec.describe V0::LettersGeneratorController, type: :controller do
  # These users are from Lighthouse API sandbox
  # https://va.ghe.com/software/vets-api-clients/blob/master/test_accounts/letter_generator_test_accounts.md
  let(:user) { build(:user, :loa3, icn: '1012666073V986297') }
  let(:user_error) { build(:user, :loa3, icn: '1012667145V762142') }
  let(:dependent_user) { build(:dependent_user_with_relationship, :loa3) }

  before do
    token = 'abcdefghijklmnop'

    allow_any_instance_of(Lighthouse::LettersGenerator::Configuration).to receive(:get_access_token).and_return(token)
  end

  describe '#index' do
    before { sign_in_as(user) }

    it 'lists letters available to the user' do
      VCR.use_cassette('lighthouse/letters_generator/index') do
        get(:index)

        letters_response = JSON.parse(response.body)
        expected_important_key = 'letters'
        expect(letters_response).to include(expected_important_key)
      end
    end
  end

  describe '#download' do
    context 'without options' do
      before { sign_in_as(user) }

      it 'returns a pdf' do
        VCR.use_cassette('lighthouse/letters_generator/download') do
          post :download, params: { id: 'BENEFIT_SUMMARY' }

          expect(response.header['Content-Type']).to eq('application/pdf')
        end
      end
    end

    context 'with options' do
      before { sign_in_as(user) }

      let(:options) do
        {
          id: 'BENEFIT_SUMMARY',
          'military_service' => true,
          'service_connected_disabilities' => true,
          'service_connected_evaluation' => false,
          'non_service_connected_pension' => false,
          'monthly_award' => false,
          'unemployable' => false,
          'special_monthly_compensation' => false,
          'adapted_housing' => false,
          'chapter35_eligibility' => false,
          'death_result_of_disability' => false,
          'survivors_award' => false
        }
      end

      it 'returns a pdf' do
        VCR.use_cassette('lighthouse/letters_generator/download_with_options') do
          post :download, params: options
          expect(response.header['Content-Type']).to eq('application/pdf')
        end
      end
    end

    context 'when an error occurs' do
      before { sign_in_as(user_error) }

      it 'raises an unprocessable entity error if upstream cannot process request' do
        VCR.use_cassette('lighthouse/letters_generator/download_error') do
          post :download, params: { id: 'BENEFIT_SUMMARY' }
          response_body = JSON.parse(response.body)
          expect(response_body['errors'].first).to include('status' => '422')
        end
      end

      it 'returns the reason the letter could not be generated instead of the upstream jargon' do
        VCR.use_cassette('lighthouse/letters_generator/download_error') do
          post :download, params: { id: 'BENEFIT_SUMMARY' }

          expect(JSON.parse(response.body)['errors'].first).to include(
            'reason' => 'no_valid_address',
            'detail' => Lighthouse::LettersGenerator::DownloadFailure.message_for(
              Lighthouse::LettersGenerator::DownloadFailure::NO_VALID_ADDRESS
            )
          )
        end
      end

      it 'counts the failure by cause' do
        allow(StatsD).to receive(:increment)

        VCR.use_cassette('lighthouse/letters_generator/download_error') do
          post :download, params: { id: 'BENEFIT_SUMMARY' }
        end

        expect(StatsD).to have_received(:increment).with(
          'api.letters_generator.download.failure',
          tags: %w[reason:no_valid_address letter_type:benefit_summary source_app:unknown]
        )
      end
    end
  end

  describe '#beneficiary' do
    context 'without error' do
      before { sign_in_as(user) }

      it 'returns beneficiary data' do
        VCR.use_cassette('lighthouse/letters_generator/beneficiary') do
          get(:beneficiary)

          beneficiary_response = JSON.parse(response.body)
          expected_important_key = 'benefitInformation'
          expect(beneficiary_response).to include(expected_important_key)
        end
      end
    end
  end
end
