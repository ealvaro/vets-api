# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/oracle_health_prescription_adapter'

RSpec.describe UnifiedHealthData::Adapters::OracleHealthRenewalFlowHelper do
  subject { UnifiedHealthData::Adapters::OracleHealthPrescriptionAdapter.new(current_user) }

  let(:current_user) { double('User') }

  before do
    allow(Settings.mhv.oh_facility_checks).to receive_messages(
      renewal_flow_allowed_oh_facilities: '',
      renewal_flow_rollout_oh_facilities: ''
    )
    allow(StatsD).to receive(:increment)
  end

  describe '#compute_renewal_flow_enabled' do
    context 'when is_renewable is false' do
      it 'returns false regardless of facility' do
        expect(subject.compute_renewal_flow_enabled(false, '999', current_user)).to be false
      end

      it 'does not emit any metric' do
        subject.compute_renewal_flow_enabled(false, '999', current_user)
        expect(StatsD).not_to have_received(:increment)
      end
    end

    context 'when station is nil' do
      it 'returns false' do
        expect(subject.compute_renewal_flow_enabled(true, nil, current_user)).to be false
      end
    end

    context 'when station is an empty string' do
      it 'returns false' do
        expect(subject.compute_renewal_flow_enabled(true, '', current_user)).to be false
      end
    end

    context 'when facility is in the allowed list' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive(:renewal_flow_allowed_oh_facilities).and_return('648, 757')
      end

      it 'returns true' do
        expect(subject.compute_renewal_flow_enabled(true, '648', current_user)).to be true
      end

      it 'increments the enabled metric with station tag' do
        subject.compute_renewal_flow_enabled(true, '648', current_user)
        expect(StatsD).to have_received(:increment).with(
          'unified_health_data.prescription.renewal_flow.enabled',
          tags: ['station:648']
        )
      end
    end

    context 'when facility is in the rollout list with Flipper enabled' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive(:renewal_flow_rollout_oh_facilities).and_return('648, 692')
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_oh_renewal_message_rollout,
                                                  current_user).and_return(true)
      end

      it 'returns true' do
        expect(subject.compute_renewal_flow_enabled(true, '648', current_user)).to be true
      end

      it 'increments the rollout metric with enabled tag' do
        subject.compute_renewal_flow_enabled(true, '648', current_user)
        expect(StatsD).to have_received(:increment).with(
          'unified_health_data.prescription.renewal_flow.rollout',
          tags: ['station:648', 'enabled:true']
        )
      end
    end

    context 'when facility is in the rollout list with Flipper disabled' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive(:renewal_flow_rollout_oh_facilities).and_return('648, 692')
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_oh_renewal_message_rollout,
                                                  current_user).and_return(false)
      end

      it 'returns false' do
        expect(subject.compute_renewal_flow_enabled(true, '648', current_user)).to be false
      end

      it 'increments the rollout metric with disabled tag' do
        subject.compute_renewal_flow_enabled(true, '648', current_user)
        expect(StatsD).to have_received(:increment).with(
          'unified_health_data.prescription.renewal_flow.rollout',
          tags: ['station:648', 'enabled:false']
        )
      end
    end

    context 'when facility is not in any list (default blocked)' do
      it 'returns false' do
        expect(subject.compute_renewal_flow_enabled(true, '999', current_user)).to be false
      end

      it 'increments the blocked metric with station tag' do
        subject.compute_renewal_flow_enabled(true, '999', current_user)
        expect(StatsD).to have_received(:increment).with(
          'unified_health_data.prescription.renewal_flow.blocked',
          tags: ['station:999']
        )
      end
    end

    context 'when facility is in both allowed and rollout lists' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive_messages(
          renewal_flow_allowed_oh_facilities: '648',
          renewal_flow_rollout_oh_facilities: '648'
        )
      end

      it 'returns true (allowed takes priority)' do
        expect(subject.compute_renewal_flow_enabled(true, '648', current_user)).to be true
      end
    end

    context 'when Settings values are empty strings' do
      before do
        allow(Settings.mhv.oh_facility_checks).to receive_messages(
          renewal_flow_allowed_oh_facilities: '',
          renewal_flow_rollout_oh_facilities: ''
        )
      end

      it 'treats all facilities as default (blocked)' do
        expect(subject.compute_renewal_flow_enabled(true, '648', current_user)).to be false
      end
    end
  end
end
