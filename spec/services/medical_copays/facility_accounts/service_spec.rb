# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::Service do
  subject(:service) { described_class.new(user) }

  let(:user) { instance_double(User, icn: '1012845331V153043', uuid: 'abc-123') }
  let(:lighthouse_builder) { instance_double(MedicalCopays::FacilityAccounts::LighthouseBuilder) }
  let(:vbs_builder) { instance_double(MedicalCopays::FacilityAccounts::VBSBuilder) }

  before do
    allow(MedicalCopays::FacilityAccounts::LighthouseBuilder).to receive(:new).and_return(lighthouse_builder)
    allow(MedicalCopays::FacilityAccounts::VBSBuilder).to receive(:new).and_return(vbs_builder)
    allow(MedicalCopays::VBS::Service).to receive(:build).and_return(instance_double(MedicalCopays::VBS::Service))
    allow(Flipper).to receive(:enabled?)
      .with(:enable_facility_account_history, user)
      .and_return(payment_history_enabled)
    allow(Flipper).to receive(:enabled?).with(:enable_lighthouse_copays, user).and_return(lighthouse_copays_enabled)
    allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).with(user).and_return(cerner_user)
  end

  describe '#facility_accounts' do
    let(:payment_history_enabled) { true }
    let(:lighthouse_copays_enabled) { true }
    let(:cerner_user) { false }

    it 'returns the facilities with their total current balance' do
      facilities = [
        MedicalCopays::FacilityAccounts::FacilityAccount.new(station_id: '896', current_balance: 0.1),
        MedicalCopays::FacilityAccounts::FacilityAccount.new(station_id: '640', current_balance: 0.2)
      ]
      allow(lighthouse_builder).to receive(:build_facility_accounts).and_return(facilities)

      expect(service.facility_accounts).to eq({ total_current_balance: 0.3, facilities: })
    end

    describe 'monitoring' do
      before do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:measure).and_call_original
      end

      it 'times the build, tagged by source' do
        allow(lighthouse_builder).to receive(:build_facility_accounts).and_return([])

        service.facility_accounts

        expect(StatsD).to have_received(:measure)
          .with('api.mcp.facility_accounts.index.latency', tags: ['source:lighthouse'])
      end

      it 'counts a failure with the error class' do
        allow(lighthouse_builder).to receive(:build_facility_accounts)
          .and_raise(MedicalCopays::VBS::Service::ServiceError)

        expect { service.facility_accounts }.to raise_error(Common::Exceptions::BadGateway)
        expect(StatsD).to have_received(:increment).with(
          'api.mcp.facility_accounts.index.failure',
          tags: ['source:lighthouse', 'error:MedicalCopaysVBSServiceServiceError']
        )
      end

      [{ source: 'lighthouse', lighthouse_copays_enabled: true, builder: :lighthouse_builder },
       { source: 'vbs', lighthouse_copays_enabled: false, builder: :vbs_builder }].each do |scenario|
        context "when the source resolves to #{scenario[:source]}" do
          let(:lighthouse_copays_enabled) { scenario[:lighthouse_copays_enabled] }

          before { allow(send(scenario[:builder])).to receive(:build_facility_accounts).and_return([]) }

          it 'resolves the source once, rather than per metric emitted' do
            service.facility_accounts

            expect(Flipper).to have_received(:enabled?).with(:enable_lighthouse_copays, user).once
          end

          it "counts the success, tagged #{scenario[:source]}" do
            service.facility_accounts

            expect(StatsD).to have_received(:increment)
              .with('api.mcp.facility_accounts.index.success', tags: ["source:#{scenario[:source]}"])
          end
        end
      end

      context 'when the feature gate rejects the request' do
        let(:payment_history_enabled) { false }

        it 'counts the backstop only, since the controller should have rejected first' do
          expect { service.facility_accounts }.to raise_error(Common::Exceptions::Forbidden)

          expect(StatsD).to have_received(:increment)
            .with('api.mcp.facility_accounts.gate.backstop_tripped').once
          expect(StatsD).to have_received(:increment).once
        end
      end
    end

    context 'when an upstream copay service fails' do
      def fail_with(error_class)
        allow(lighthouse_builder).to receive(:build_facility_accounts).and_raise(error_class)
      end

      [MedicalCopays::VBS::Service::ServiceError,
       described_class::LIGHTHOUSE_UPSTREAM_500].each do |error_class|
        it "raises a bad gateway for #{error_class}, rather than blaming our own code" do
          fail_with(error_class)

          expect { service.facility_accounts }.to raise_error(Common::Exceptions::BadGateway)
        end
      end

      it 'logs who it failed for, which the platform handler cannot supply' do
        allow(Rails.logger).to receive(:error)
        fail_with(MedicalCopays::VBS::Service::ServiceError)

        expect { service.facility_accounts }.to raise_error(Common::Exceptions::BadGateway)
        expect(Rails.logger).to have_received(:error).with(
          'MedicalCopays::FacilityAccounts upstream service error',
          error_class: 'MedicalCopays::VBS::Service::ServiceError',
          user_uuid: user.uuid
        )
      end

      it 'lets our own errors through untranslated' do
        fail_with(NoMethodError)

        expect { service.facility_accounts }.to raise_error(NoMethodError)
      end
    end
  end

  describe '#facility_account' do
    let(:payment_history_enabled) { true }
    let(:lighthouse_copays_enabled) { true }
    let(:cerner_user) { false }
    let(:account) { MedicalCopays::FacilityAccounts::FacilityAccount.new(station_id: '757') }

    it 'returns the account the builder found for the station' do
      allow(lighthouse_builder).to receive(:build_facility_account).with('757').and_return(account)

      expect(service.facility_account('757')).to eq(account)
    end

    describe 'monitoring' do
      before do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:measure).and_call_original
      end

      it 'times the build and counts the success, tagged by source' do
        allow(lighthouse_builder).to receive(:build_facility_account).and_return(account)

        service.facility_account('757')

        expect(StatsD).to have_received(:measure)
          .with('api.mcp.facility_accounts.show.latency', tags: ['source:lighthouse'])
        expect(StatsD).to have_received(:increment)
          .with('api.mcp.facility_accounts.show.success', tags: ['source:lighthouse'])
      end

      it 'counts a failure with the error class' do
        allow(lighthouse_builder).to receive(:build_facility_account)
          .and_raise(MedicalCopays::VBS::Service::ServiceError)

        expect { service.facility_account('757') }.to raise_error(Common::Exceptions::BadGateway)
        expect(StatsD).to have_received(:increment).with(
          'api.mcp.facility_accounts.show.failure',
          tags: ['source:lighthouse', 'error:MedicalCopaysVBSServiceServiceError']
        )
      end

      context 'when the station has no account' do
        before { allow(lighthouse_builder).to receive(:build_facility_account).and_return(nil) }

        it 'records a not_found, not a failure' do
          expect(service.facility_account('757')).to be_nil

          expect(StatsD).to have_received(:increment)
            .with('api.mcp.facility_accounts.show.not_found', tags: ['source:lighthouse'])
          expect(StatsD).not_to have_received(:increment)
            .with('api.mcp.facility_accounts.show.failure', anything)
        end

        it 'logs the station id' do
          allow(Rails.logger).to receive(:warn)

          service.facility_account('757')

          expect(Rails.logger).to have_received(:warn).with(
            'MedicalCopays::FacilityAccounts no account found',
            station_id: '757',
            user_uuid: user.uuid
          )
        end
      end
    end
  end

  describe 'feature gating' do
    context 'when enable_facility_account_history is disabled' do
      let(:payment_history_enabled) { false }
      let(:lighthouse_copays_enabled) { true }
      let(:cerner_user) { false }

      { facility_accounts: [], facility_account: ['896'], statements: ['896'] }.each do |method, args|
        it "forbids #{method}" do
          expect { service.public_send(method, *args) }.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    [{ lighthouse_copays_enabled: true, cerner_user: false, builder: :lighthouse_builder },
     { lighthouse_copays_enabled: true, cerner_user: true, builder: :vbs_builder },
     { lighthouse_copays_enabled: false, cerner_user: false, builder: :vbs_builder }].each do |scenario|
      context "with enable_lighthouse_copays #{scenario[:lighthouse_copays_enabled]} and a " \
              "#{scenario[:cerner_user] ? 'Cerner' : 'non-Cerner'} user" do
        let(:payment_history_enabled) { true }
        let(:lighthouse_copays_enabled) { scenario[:lighthouse_copays_enabled] }
        let(:cerner_user) { scenario[:cerner_user] }

        it "serves accounts from the #{scenario[:builder]}" do
          builder = send(scenario[:builder])
          allow(builder).to receive(:build_facility_accounts).and_return([])

          service.facility_accounts

          expect(builder).to have_received(:build_facility_accounts)
        end
      end
    end
  end
end
