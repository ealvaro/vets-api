# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::Service do
  subject(:service) { described_class.new(user) }

  let(:user) { instance_double(User, icn: '1012845331V153043') }
  let(:lighthouse_builder) { instance_double(MedicalCopays::FacilityAccounts::LighthouseBuilder) }
  let(:vbs_builder) { instance_double(MedicalCopays::FacilityAccounts::VBSBuilder) }

  before do
    allow(MedicalCopays::FacilityAccounts::LighthouseBuilder).to receive(:new).and_return(lighthouse_builder)
    allow(MedicalCopays::FacilityAccounts::VBSBuilder).to receive(:new).and_return(vbs_builder)
    allow(MedicalCopays::VBS::Service).to receive(:build).and_return(instance_double(MedicalCopays::VBS::Service))
    allow(Flipper).to receive(:enabled?).with(:enable_copays_payment_history, user).and_return(payment_history_enabled)
    allow(Flipper).to receive(:enabled?).with(:enable_lighthouse_copays, user).and_return(lighthouse_copays_enabled)
  end

  describe '#accounts' do
    let(:payment_history_enabled) { true }
    let(:lighthouse_copays_enabled) { true }

    it 'returns the facilities with their total current balance' do
      facilities = [
        MedicalCopays::FacilityAccounts::FacilityAccount.new(station_id: '896', current_balance: 0.1),
        MedicalCopays::FacilityAccounts::FacilityAccount.new(station_id: '640', current_balance: 0.2)
      ]
      allow(lighthouse_builder).to receive(:build_facility_accounts).and_return(facilities)

      expect(service.accounts).to eq({ total_current_balance: 0.3, facilities: })
    end
  end

  describe 'feature gating' do
    context 'when enable_copays_payment_history is disabled' do
      let(:payment_history_enabled) { false }
      let(:lighthouse_copays_enabled) { true }

      it 'forbids accounts' do
        expect { service.accounts }.to raise_error(Common::Exceptions::Forbidden)
      end

      it 'forbids account' do
        expect { service.account('896') }.to raise_error(Common::Exceptions::Forbidden)
      end

      it 'forbids statements' do
        expect { service.statements('896') }.to raise_error(Common::Exceptions::Forbidden)
      end
    end

    context 'when enable_copays_payment_history and enable_lighthouse_copays are enabled' do
      let(:payment_history_enabled) { true }
      let(:lighthouse_copays_enabled) { true }

      it 'serves accounts from the Lighthouse builder' do
        allow(lighthouse_builder).to receive(:build_facility_accounts).and_return([])

        service.accounts

        expect(lighthouse_builder).to have_received(:build_facility_accounts)
      end
    end

    context 'when enable_copays_payment_history is enabled but enable_lighthouse_copays is disabled' do
      let(:payment_history_enabled) { true }
      let(:lighthouse_copays_enabled) { false }

      it 'serves accounts from the VBS builder' do
        allow(vbs_builder).to receive(:build_facility_accounts).and_return([])

        service.accounts

        expect(vbs_builder).to have_received(:build_facility_accounts)
      end
    end
  end
end
