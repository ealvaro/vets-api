# frozen_string_literal: true

require 'rails_helper'
require 'hca/enrollment_eligibility/service'

EMERGENCY_CONTACTS_KEYS = %w[nextOfKins emergencyContacts].freeze
SERVICE_HISTORY_KEYS = %w[lastServiceBranch lastEntryDate lastDischargeDate dischargeType].freeze

describe HCA::EnrollmentEligibility::Service do
  let(:user) do
    create(
      :evss_user,
      :loa3,
      icn: '1012829228V424035',
      birth_date: '1963-07-05',
      first_name: 'FirstName',
      middle_name: 'MiddleName',
      last_name: 'ZZTEST',
      suffix: 'Jr.',
      ssn: '111111234',
      gender: 'F'
    )
  end

  describe '#get_ezr_data' do
    let(:service_history) do
      instance_double(
        VAProfile::Prefill::MilitaryInformation,
        hca_last_service_branch: 'air force',
        last_entry_date: '1992-08-26',
        last_discharge_date: '2017-08-30',
        discharge_type: 'honorable'
      )
    end
    let(:veteran_data_without_contacts_or_service_history) do
      veteran_data_without_service_history.except(*EMERGENCY_CONTACTS_KEYS)
    end
    let(:veteran_data_without_service_history) { veteran_data.except(*SERVICE_HISTORY_KEYS) }
    let(:veteran_data) do
      data = JSON.parse(File.read('spec/fixtures/form1010_ezr/veteran_data.json'))
      financial_info = data['nonPrefill']['previousFinancialInfo']

      data.delete('nonPrefill')
      data.merge('previousFinancialInfo' => financial_info)
    end

    context 'with a blank icn' do
      it 'raises InvalidIcnError' do
        user_without_icn = double(icn: '')

        expect { described_class.new.get_ezr_data(user_without_icn) }
          .to raise_error(described_class::InvalidIcnError)
      end
    end

    def expect_veteran_data_to_match(veteran_data)
      VCR.use_cassette(
        'form1010_ezr/lookup_user_with_ezr_prefill_data',
        match_requests_on: %i[method uri body], erb: true
      ) do
        expect(
          described_class.new.get_ezr_data(
            user,
            service_history
          ).to_h.deep_stringify_keys
        ).to eq(veteran_data)
      end
    end

    context 'ezr_service_history_enabled feature flag' do
      context 'when disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:ezr_service_history_enabled, user).and_return(false)
        end

        it 'gets Veteran data without service history' do
          expect_veteran_data_to_match(veteran_data_without_service_history)
        end
      end

      context 'when enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:ezr_service_history_enabled, user).and_return(true)
        end

        context 'when VAProfile responds' do
          it 'gets Veteran data with service history' do
            expect_veteran_data_to_match(veteran_data)
          end

          context 'with service history data' do
            let(:service_history) do
              instance_double(
                VAProfile::Prefill::MilitaryInformation,
                hca_last_service_branch: 'air force',
                last_entry_date: '1992-01-01',
                last_discharge_date: '2000-01-01',
                discharge_type: 'honorable'
              )
            end

            it 'gets Veteran data with service history' do
              latest_service_data = {
                'lastServiceBranch' => 'air force',
                'lastEntryDate' => '1992-01-01',
                'lastDischargeDate' => '2000-01-01',
                'dischargeType' => 'honorable'
              }

              expect_veteran_data_to_match(veteran_data.merge(latest_service_data))
            end
          end
        end
      end
    end

    context "when 'ezr_emergency_contacts_enabled' flipper is disabled" do
      before do
        allow(Flipper).to receive(:enabled?).with(:ezr_emergency_contacts_enabled, user).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:ezr_service_history_enabled, user).and_return(false)
      end

      it 'gets Veteran data without contacts and with providers and dependents' do
        expect_veteran_data_to_match(veteran_data_without_contacts_or_service_history)
      end
    end

    context "when 'ezr_emergency_contacts_enabled' flipper is enabled" do
      before do
        allow(Flipper).to receive(:enabled?).with(:ezr_emergency_contacts_enabled, user).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:ezr_service_history_enabled, user).and_return(false)
      end

      it 'gets Veteran data with contacts, providers and dependents' do
        expect_veteran_data_to_match(veteran_data_without_service_history)
      end
    end
  end

  describe '#parse_es_date' do
    context 'with an invalid date' do
      it 'returns nil and logs the date' do
        date_str = 'f'
        service = described_class.new

        expect(Rails.logger).to receive(:error).with(
          '[HCA] - DateError',
          { exception: instance_of(Date::Error) }
        )

        expect(
          service.send(:parse_es_date, date_str)
        ).to be_nil

        expect(
          PersonalInformationLog.where(error_class: 'Form1010Ezr DateError').last.data
        ).to eq(date_str)
      end
    end
  end

  describe '#lookup_user' do
    context 'with a blank icn' do
      it 'raises InvalidIcnError' do
        expect { described_class.new.lookup_user('') }
          .to raise_error(described_class::InvalidIcnError, 'ICN is required to look up EE data')
      end
    end

    context 'with a nil icn' do
      it 'raises InvalidIcnError' do
        expect { described_class.new.lookup_user(nil) }
          .to raise_error(described_class::InvalidIcnError, 'ICN is required to look up EE data')
      end
    end

    context 'with a user that has an ineligibility_reason' do
      it 'gets the ineligibility_reason', run_at: 'Wed, 13 Feb 2019 09:20:47 GMT' do
        VCR.use_cassette(
          'hca/ee/lookup_user_ineligibility_reason',
          VCR::MATCH_EVERYTHING.merge(erb: true)
        ) do
          expect(
            described_class.new.lookup_user('0000001013030524V532318000000')
          ).to eq(
            enrollment_status: 'Not Eligible; Ineligible Date',
            application_date: '2018-01-24T00:00:00.000-06:00',
            enrollment_date: nil,
            preferred_facility: '987 - CHEY6',
            ineligibility_reason: 'for testing',
            effective_date: '2019-01-25T09:04:04.000-06:00',
            primary_eligibility: 'HUMANITARIAN EMERGENCY',
            veteran: 'false',
            priority_group: nil,
            can_submit_financial_info: true
          )
        end
      end
    end

    context "when the user's financial info has already been submitted for the prior calendar year" do
      before { Timecop.freeze(DateTime.new(2023, 2, 3)) }
      after { Timecop.return }

      it "sets the 'can_submit_financial_info' key to false", run_at: 'Mon, 04 Dec 2023 22:32:14 GMT' do
        VCR.use_cassette(
          'hca/ee/lookup_user_can_submit_financial_info',
          { match_requests_on: %i[method uri body], erb: true }
        ) do
          expect(
            described_class.new.lookup_user('1013144622V807216')
          ).to eq(
            enrollment_status: 'Pending; Other',
            application_date: nil,
            enrollment_date: nil,
            preferred_facility: nil,
            ineligibility_reason: nil,
            effective_date: '2019-09-08T22:23:05.000-05:00',
            primary_eligibility: 'NSC',
            veteran: 'true',
            priority_group: nil,
            can_submit_financial_info: false
          )
        end
      end
    end

    it 'lookups the user through the hca ee api', run_at: 'Fri, 08 Feb 2019 02:50:45 GMT' do
      VCR.use_cassette(
        'hca/ee/lookup_user',
        VCR::MATCH_EVERYTHING.merge(erb: true)
      ) do
        expect(
          described_class.new.lookup_user('1013032368V065534')
        ).to eq(
          enrollment_status: 'Verified',
          application_date: '2018-12-27T00:00:00.000-06:00',
          enrollment_date: '2018-12-27T17:15:39.000-06:00',
          preferred_facility: '988 - DAYT20',
          ineligibility_reason: nil,
          effective_date: '2019-01-02T21:58:55.000-06:00',
          primary_eligibility: 'SC LESS THAN 50%',
          veteran: 'true',
          priority_group: 'Group 3',
          can_submit_financial_info: true
        )
      end
    end
  end
end
