# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::SessionRecordCleanUpJob, type: :job do
  subject { described_class.new.perform }

  let(:retention_period) { described_class::RETENTION_PERIOD }

  describe '#perform' do
    context 'with a record signed out more than 30 days ago' do
      let!(:stale_record) { create(:session_record, signed_out_at: (retention_period + 1.day).ago) }

      it 'deletes it' do
        expect { subject }.to change(SignIn::SessionRecord, :count).by(-1)
        expect(SignIn::SessionRecord.where(id: stale_record.id)).not_to exist
      end

      it 'returns the deleted count' do
        expect(subject).to eq(1)
      end
    end

    context 'with a record signed out less than 30 days ago' do
      let!(:recent_record) { create(:session_record, signed_out_at: (retention_period - 1.day).ago) }

      it 'leaves it alone' do
        expect { subject }.not_to change(SignIn::SessionRecord, :count)
        expect(SignIn::SessionRecord.where(id: recent_record.id)).to exist
      end
    end

    context 'with a record signed out exactly 30 days ago' do
      around { |example| Timecop.freeze(Time.zone.now) { example.run } }

      let!(:boundary_record) { create(:session_record, signed_out_at: retention_period.ago) }

      it 'leaves it alone' do
        expect { subject }.not_to change(SignIn::SessionRecord, :count)
        expect(SignIn::SessionRecord.where(id: boundary_record.id)).to exist
      end
    end

    context 'with an active record' do
      let!(:active_record) { create(:session_record, signed_out_at: nil) }

      it 'leaves it alone' do
        expect { subject }.not_to change(SignIn::SessionRecord, :count)
        expect(SignIn::SessionRecord.where(id: active_record.id)).to exist
      end
    end

    context 'with a mix of records' do
      let!(:stale_records) { create_list(:session_record, 3, signed_out_at: (retention_period + 1.day).ago) }
      let!(:recent_record) { create(:session_record, signed_out_at: 1.day.ago) }
      let!(:active_record) { create(:session_record, signed_out_at: nil) }

      it 'deletes only the stale records' do
        expect { subject }.to change(SignIn::SessionRecord, :count).by(-3)
        expect(SignIn::SessionRecord.pluck(:id)).to contain_exactly(recent_record.id, active_record.id)
      end

      it 'logs the deleted count' do
        expect_any_instance_of(SignIn::Logger).to receive(:info)
          .with('signed out session records purged', { deleted_count: 3 })
        subject
      end
    end

    context 'when there is nothing to purge' do
      it 'does not raise' do
        expect { subject }.not_to raise_error
      end

      it 'returns zero' do
        expect(subject).to eq(0)
      end
    end
  end
end
