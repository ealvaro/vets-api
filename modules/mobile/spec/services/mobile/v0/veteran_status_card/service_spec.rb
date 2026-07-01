# frozen_string_literal: true

require_relative '../../../../support/helpers/rails_helper'
require 'mobile/v0/veteran_status_card/service'

RSpec.describe Mobile::V0::VeteranStatusCard::Service do
  subject { described_class.new(user) }

  let(:user) { build(:user, :loa3) }

  # Mock responses
  let(:vet_verification_service) { instance_double(VeteranVerification::Service) }
  let(:military_personnel_service) { instance_double(VAProfile::MilitaryPersonnel::Service) }
  let(:lighthouse_disabilities_provider) { instance_double(LighthouseRatedDisabilitiesProvider) }

  # Default mock data
  let(:vet_verification_response) do
    {
      'data' => {
        'attributes' => {
          'veteran_status' => veteran_status,
          'not_confirmed_reason' => not_confirmed_reason
        },
        'message' => error_message,
        'title' => error_title,
        'status' => error_status
      }
    }
  end

  let(:veteran_status) { 'confirmed' }
  let(:not_confirmed_reason) { nil }
  let(:error_message) { '' }
  let(:error_title) { '' }
  let(:error_status) { '' }

  let(:dod_service_summary_response) do
    instance_double(
      VAProfile::MilitaryPersonnel::DodServiceSummaryResponse,
      dod_service_summary: dod_service_summary_model
    )
  end

  let(:dod_service_summary_model) do
    VAProfile::Models::DodServiceSummary.new(
      dod_service_summary_code: ssc_code,
      calculation_model_version: '1.0',
      effective_start_date: '2020-01-01'
    )
  end

  let(:ssc_code) { 'A1' }

  let(:disability_rating) { 50 }

  before do
    allow(VeteranVerification::Service).to receive(:new).and_return(vet_verification_service)
    allow(vet_verification_service).to receive(:get_vet_verification_status).and_return(vet_verification_response)

    allow(VAProfile::MilitaryPersonnel::Service).to receive(:new).and_return(military_personnel_service)
    allow(military_personnel_service).to receive(:get_dod_service_summary).and_return(dod_service_summary_response)

    allow(LighthouseRatedDisabilitiesProvider).to receive(:new).and_return(lighthouse_disabilities_provider)
    allow(lighthouse_disabilities_provider).to receive(:get_combined_disability_rating).and_return(disability_rating)
  end

  describe 'inheritance' do
    it 'inherits from VeteranStatusCard::Service' do
      expect(described_class.superclass).to eq(VeteranStatusCard::Service)
    end
  end

  describe 'protected method overrides' do
    describe '#statsd_key_prefix' do
      it 'returns Mobile-specific prefix' do
        expect(subject.send(:statsd_key_prefix)).to eq('veteran_status_card.mobile')
      end
    end

    describe '#service_name' do
      it 'returns Mobile-specific service name' do
        expect(subject.send(:service_name)).to eq('[Mobile::V0::VeteranStatusCard::Service]')
      end
    end

    describe '#something_went_wrong_response' do
      it 'returns Mobile constants' do
        expect(subject.send(:something_went_wrong_response)).to eq(
          Mobile::V0::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_RESPONSE
        )
      end
    end

    describe '#discharge_status_response' do
      it 'returns Mobile constants' do
        expect(subject.send(:discharge_status_response)).to eq(
          Mobile::V0::VeteranStatusCard::Constants::DISCHARGE_STATUS_RESPONSE
        )
      end
    end

    describe '#unknown_eligibility_response' do
      it 'returns Mobile constants' do
        expect(subject.send(:unknown_eligibility_response)).to eq(
          Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE
        )
      end
    end

    describe '#currently_serving_response' do
      it 'returns Mobile constants' do
        expect(subject.send(:currently_serving_response)).to eq(
          Mobile::V0::VeteranStatusCard::Constants::CURRENTLY_SERVING_RESPONSE
        )
      end
    end

    describe '#person_not_found_response' do
      it 'returns Mobile constants' do
        expect(subject.send(:person_not_found_response)).to eq(
          Mobile::V0::VeteranStatusCard::Constants::PERSON_NOT_FOUND_RESPONSE
        )
      end
    end
  end

  describe '#initialize' do
    before do
      allow(StatsD).to receive(:increment)
    end

    context 'when user is valid' do
      it 'logs STATSD_TOTAL with mobile prefix' do
        described_class.new(user)

        expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.total')
      end

      it 'does not log STATSD_FAILURE' do
        described_class.new(user)

        expect(StatsD).not_to have_received(:increment).with('veteran_status_card.mobile.failure')
      end
    end

    context 'when user is nil' do
      it 'does not raise an error' do
        expect { described_class.new(nil) }.not_to raise_error
      end

      it 'only logs STATSD_TOTAL with mobile prefix' do
        described_class.new(nil)

        expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.total')
        expect(StatsD).not_to have_received(:increment).with('veteran_status_card.mobile.failure')
      end
    end

    context 'when user edipi and icn are nil' do
      before do
        allow(user).to receive_messages(edipi: nil, icn: nil)
      end

      it 'does not raise an error' do
        expect { described_class.new(user) }.not_to raise_error
      end

      it 'only logs STATSD_TOTAL with mobile prefix' do
        described_class.new(user)

        expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.total')
        expect(StatsD).not_to have_received(:increment).with('veteran_status_card.mobile.failure')
      end
    end
  end

  describe '#status_card' do
    describe 'StatsD logging with mobile prefix' do
      before do
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
      end

      context 'when veteran is eligible' do
        let(:veteran_status) { 'confirmed' }

        it 'logs STATSD_ELIGIBLE with mobile prefix' do
          subject.status_card

          expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.eligible')
        end

        it 'logs VSC Card Result info with mobile service name' do
          subject.status_card

          expect(Rails.logger).to have_received(:info).with(
            '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
            hash_including(
              veteran_status: 'confirmed',
              service_summary_code: ssc_code
            )
          )
        end
      end

      context 'when veteran is not eligible' do
        let(:veteran_status) { 'not confirmed' }
        let(:not_confirmed_reason) { 'PERSON_NOT_FOUND' }

        it 'logs STATSD_INELIGIBLE with mobile prefix' do
          subject.status_card

          expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.ineligible')
        end

        it 'logs VSC Card Result info with mobile service name' do
          subject.status_card

          expect(Rails.logger).to have_received(:info).with(
            '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
            hash_including(
              veteran_status: 'not confirmed',
              not_confirmed_reason: 'PERSON_NOT_FOUND',
              service_summary_code: ssc_code
            )
          )
        end
      end

      context 'when an exception occurs' do
        let(:veteran_status) { 'confirmed' }

        before do
          allow(user).to receive(:full_name_normalized).and_raise(StandardError.new('Test error'))
        end

        it 'logs STATSD_FAILURE with mobile prefix' do
          subject.status_card

          expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.failure')
        end

        it 'logs error with mobile service name' do
          subject.status_card

          expect(Rails.logger).to have_received(:error).with(
            '[Mobile::V0::VeteranStatusCard::Service] error: Test error',
            hash_including(:backtrace)
          )
        end
      end

      describe 'ineligibility reason StatsD logging with mobile prefix' do
        context 'with DISCHARGE_STATUS SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'A5' }

          it 'logs DISCHARGE_STATUS_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment)
              .with('veteran_status_card.mobile.ineligible_discharge_status_ssc')
          end
        end

        context 'with UNKNOWN_SERVICE SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'U' }

          it 'logs UNKNOWN_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.ineligible_unknown_ssc')
          end
        end

        context 'with EDIPI_NO_PNL SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'X' }

          it 'logs UNKNOWN_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.ineligible_unknown_ssc')
          end
        end

        context 'with CURRENTLY_SERVING SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'D' }

          it 'logs CURRENTLY_SERVING_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment)
              .with('veteran_status_card.mobile.ineligible_currently_serving_ssc')
          end
        end

        context 'with ERROR SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'VNA' }

          it 'logs UNKNOWN_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.ineligible_unknown_ssc')
          end
        end

        context 'with uncaught SSC code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'UNKNOWN_CODE' }

          it 'logs UNCAUGHT_SSC_MESSAGE with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.ineligible_uncaught_ssc')
          end
        end

        context 'with PERSON_NOT_FOUND reason' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'PERSON_NOT_FOUND' }

          it 'logs the vet_verification_status reason with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.person_not_found')
          end
        end

        context 'with ERROR reason' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'ERROR' }
          let(:error_title) { 'Error' }
          let(:error_message) { 'An error occurred' }
          let(:error_status) { 'error' }

          it 'logs the vet_verification_status reason with mobile prefix' do
            subject.status_card

            expect(StatsD).to have_received(:increment).with('veteran_status_card.mobile.error')
          end
        end
      end

      describe 'user_message logging' do
        context 'when user is missing ICN' do
          before do
            allow(user).to receive(:icn).and_return(nil)
          end

          it 'logs user_message: person_not_found' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::PERSON_NOT_FOUND_MESSAGE)
            )
          end
        end

        context 'when user is missing EDIPI but vet verification is not confirmed' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }

          before do
            allow(user).to receive(:edipi).and_return(nil)
          end

          it 'logs user_message: person_not_found' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::PERSON_NOT_FOUND_MESSAGE)
            )
          end
        end

        context 'when veteran is confirmed via vet verification' do
          let(:veteran_status) { 'confirmed' }

          it 'logs user_message: status_card_confirmed' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::CONFIRMED_MESSAGE)
            )
          end
        end

        context 'when veteran is confirmed via SSC' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'A1' }

          it 'logs user_message: status_card_confirmed' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::CONFIRMED_MESSAGE)
            )
          end
        end

        context 'when vet verification reason is PERSON_NOT_FOUND' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'PERSON_NOT_FOUND' }

          it 'logs user_message: person_not_found' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::PERSON_NOT_FOUND_MESSAGE)
            )
          end
        end

        context 'when vet verification reason is ERROR' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'ERROR' }

          it 'logs user_message: something_went_wrong' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::SOMETHING_WENT_WRONG_MESSAGE)
            )
          end
        end

        context 'when SSC code is discharge status ineligible' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'A5' }

          it 'logs user_message: discharge_status' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::DISCHARGE_STATUS_MESSAGE)
            )
          end
        end

        context 'when SSC code is unknown service' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'U' }

          it 'logs user_message: unknown_eligibility' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::UNKNOWN_ELIGIBILITY_MESSAGE)
            )
          end
        end

        context 'when SSC code is EDIPI_NO_PNL' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'X' }

          it 'logs user_message: unknown_eligibility' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::UNKNOWN_ELIGIBILITY_MESSAGE)
            )
          end
        end

        context 'when SSC code is currently serving' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'D' }

          it 'logs user_message: currently_serving' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::CURRENTLY_SERVING_MESSAGE)
            )
          end
        end

        context 'when SSC code is an error code' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'VNA' }

          it 'logs user_message: unknown_eligibility' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::UNKNOWN_ELIGIBILITY_MESSAGE)
            )
          end
        end

        context 'when SSC code is uncaught' do
          let(:veteran_status) { 'not confirmed' }
          let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
          let(:ssc_code) { 'UNKNOWN_CODE' }

          it 'logs user_message: unknown_eligibility' do
            subject.status_card

            expect(Rails.logger).to have_received(:info).with(
              '[Mobile::V0::VeteranStatusCard::Service] VSC Card Result',
              hash_including(user_message: described_class::UNKNOWN_ELIGIBILITY_MESSAGE)
            )
          end
        end
      end
    end

    context 'when veteran is eligible' do
      let(:veteran_status) { 'confirmed' }

      it 'returns veteran_status_card with full veteran data' do
        result = subject.status_card

        expect(result[:type]).to eq('veteran_status_card')
        expect(result[:attributes][:full_name]).to be_a(String)
        expect(result[:attributes][:disability_rating]).to eq(50)
        expect(result[:attributes][:edipi]).to eq(user.edipi)
        expect(result[:attributes][:veteran_status]).to eq('confirmed')
        expect(result[:attributes][:not_confirmed_reason]).to be_nil
        expect(result[:attributes][:service_summary_code]).to eq(ssc_code)
      end
    end

    context 'when veteran is not eligible' do
      let(:veteran_status) { 'not confirmed' }

      context 'with DISCHARGE_STATUS SSC codes' do
        let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
        let(:ssc_code) { 'A5' }

        it 'returns veteran_status_alert with Mobile discharge status constants' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          discharge_response = Mobile::V0::VeteranStatusCard::Constants::DISCHARGE_STATUS_RESPONSE
          expect(result[:attributes][:header]).to eq(discharge_response[:title])
          expect(result[:attributes][:body]).to eq(discharge_response[:message])
          expect(result[:attributes][:alert_type]).to eq(discharge_response[:status])
          expect(result[:attributes][:veteran_status]).to eq('not confirmed')
          expect(result[:attributes][:not_confirmed_reason]).to eq('MORE_RESEARCH_REQUIRED')
          expect(result[:attributes][:service_summary_code]).to eq(ssc_code)
        end
      end

      context 'with UNKNOWN_SERVICE SSC code' do
        let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
        let(:ssc_code) { 'U' }

        it 'returns veteran_status_alert with Mobile unknown eligibility constants' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:message])
          expect(result[:attributes][:alert_type]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:status])
        end
      end

      context 'with EDIPI_NO_PNL SSC code' do
        let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
        let(:ssc_code) { 'X' }

        it 'returns veteran_status_alert with Mobile unknown eligibility constants' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:message])
          expect(result[:attributes][:alert_type]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:status])
        end
      end

      context 'with CURRENTLY_SERVING SSC codes' do
        let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
        let(:ssc_code) { 'D' }

        it 'returns veteran_status_alert with Mobile currently serving constants' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::CURRENTLY_SERVING_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::CURRENTLY_SERVING_RESPONSE[:message])
          expect(result[:attributes][:alert_type]).to eq(Mobile::V0::VeteranStatusCard::Constants::CURRENTLY_SERVING_RESPONSE[:status])
        end
      end

      context 'with ERROR SSC codes' do
        let(:not_confirmed_reason) { 'MORE_RESEARCH_REQUIRED' }
        let(:ssc_code) { 'VNA' }

        it 'returns veteran_status_alert with Mobile unknown eligibility constants' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:message])
          expect(result[:attributes][:alert_type]).to eq(Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE[:status])
        end
      end
    end

    context 'error scenarios' do
      context 'when user is nil' do
        let(:user) { nil }

        before do
          allow(StatsD).to receive(:increment)
          allow(Rails.logger).to receive(:info)
        end

        it 'returns a veteran_status_alert with Mobile person_not_found details' do
          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::PERSON_NOT_FOUND_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::PERSON_NOT_FOUND_RESPONSE[:message])
          expect(result[:attributes][:veteran_status]).to eq('not confirmed')
          expect(result[:attributes][:not_confirmed_reason]).to eq('PERSON_NOT_FOUND')
          expect(result[:attributes][:confirmation_status]).to eq('INELIGIBLE_NO_ICN')
        end
      end

      context 'when top-level exception occurs' do
        let(:veteran_status) { 'confirmed' }

        before do
          allow(user).to receive(:full_name_normalized).and_raise(StandardError.new('Unexpected error'))
        end

        it 'logs the error and returns Mobile SOMETHING_WENT_WRONG_RESPONSE' do
          expect(Rails.logger).to receive(:error).with(/Mobile::V0::VeteranStatusCard::Service.*error/, anything)

          result = subject.status_card

          expect(result[:type]).to eq('veteran_status_alert')
          expect(result[:attributes][:header]).to eq(Mobile::V0::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_RESPONSE[:title])
          expect(result[:attributes][:body]).to eq(Mobile::V0::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_RESPONSE[:message])
          expect(result[:attributes][:alert_type]).to eq(Mobile::V0::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_RESPONSE[:status])
        end
      end
    end

    context 'when user is +6' do
      let(:user) { build(:user, email: 'vets.gov.user+6@gmail.com') }

      context 'when environment in not production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

        it 'returns ineligible_response for currently serving' do
          response = subject.status_card

          expect(response[:attributes][:confirmation_status])
            .to eq(described_class::CURRENTLY_SERVING_SSC_MESSAGE.upcase)
          expect(response[:attributes][:service_summary_code]).to eq('D')
        end
      end

      context 'when environment is production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('production') }

        it 'does not trigger special test cases, continues regular logic' do
          expect_any_instance_of(described_class).not_to receive(:ineligible_response)
          subject.status_card
        end
      end
    end

    context 'when user is +7' do
      let(:user) { build(:user, email: 'vets.gov.user+7@gmail.com') }

      context 'when environment in not production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

        it 'returns ineligible_response for discharge status' do
          response = subject.status_card

          expect(response[:attributes][:confirmation_status])
            .to eq(described_class::DISCHARGE_STATUS_SSC_MESSAGE.upcase)
          expect(response[:attributes][:service_summary_code]).to eq('A5')
        end
      end

      context 'when environment is production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('production') }

        it 'does not trigger special test cases, continues regular logic' do
          expect_any_instance_of(described_class).not_to receive(:ineligible_response)
          subject.status_card
        end
      end
    end

    context 'when user is +8' do
      let(:user) { build(:user, email: 'vets.gov.user+8@gmail.com') }

      context 'when environment is not production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

        it 'returns ineligible_response for unknown eligibility' do
          response = subject.status_card

          expect(response[:attributes][:confirmation_status]).to eq(described_class::UNKNOWN_SSC_MESSAGE.upcase)
          expect(response[:attributes][:service_summary_code]).to eq('U')
        end
      end

      context 'when environment is production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('production') }

        it 'does not trigger special test cases, continues regular logic' do
          expect_any_instance_of(described_class).not_to receive(:ineligible_response)
          subject.status_card
        end
      end
    end

    context 'when user is +9' do
      let(:user) { build(:user, email: 'vets.gov.user+9@gmail.com') }

      context 'when environment is not production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

        it 'returns person not found response' do
          response = subject.status_card

          expect(response[:attributes][:confirmation_status]).to eq(described_class::PERSON_NOT_FOUND_MESSAGE.upcase)
          expect(response[:attributes][:service_summary_code]).to be_nil
        end
      end

      context 'when environment is production' do
        before { allow(Settings).to receive(:vsp_environment).and_return('production') }

        it 'does not trigger special test cases, continues regular logic' do
          expect_any_instance_of(described_class).not_to receive(:person_not_found_response_hash)
          subject.status_card
        end
      end
    end

    context 'when user is not a test user' do
      let(:user) { build(:user, email: 'normal.user@example.com') }

      it 'does not trigger special test cases, continues regular logic' do
        expect_any_instance_of(described_class).not_to receive(:ineligible_response)
        subject.status_card
      end
    end
  end
end
