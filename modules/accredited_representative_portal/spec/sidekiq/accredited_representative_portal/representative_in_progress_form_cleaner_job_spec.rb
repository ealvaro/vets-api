# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::RepresentativeInProgressFormCleanerJob do
  describe '#perform' do
    let(:now) { Time.now.utc }

    context 'when a form is older than 60 days' do
      before do
        Timecop.freeze(now - 61.days)
        @form_expired = create(:representative_in_progress_form)
        Timecop.return
      end

      it 'deletes the expired form' do
        expect { subject.perform }
          .to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count).by(-1)
        expect { @form_expired.reload }.to raise_exception(ActiveRecord::RecordNotFound)
      end
    end

    context 'when a form is within 60 days' do
      before do
        Timecop.freeze(now - 59.days)
        @form_active = create(:representative_in_progress_form)
        Timecop.return
      end

      it 'does not delete the form' do
        expect { subject.perform }
          .not_to change(AccreditedRepresentativePortal::RepresentativeInProgressForm, :count)
        expect { @form_active.reload }.not_to raise_exception
      end
    end

    context 'when tracking form deletions' do
      it 'increments stats for each form_id' do
        Timecop.freeze(now - 61.days)
        create(:representative_in_progress_form, veteran_icn: '1111111111V111111', form_id: 'form-1')
        create(:representative_in_progress_form, veteran_icn: '2222222222V222222', form_id: 'form-1')
        create(:representative_in_progress_form, veteran_icn: '3333333333V333333', form_id: 'form-2')
        Timecop.return

        expect(StatsD).to receive(:increment)
          .with('worker.arp.representative_in_progress_form_cleaner.form_1_deleted', 2)
        expect(StatsD).to receive(:increment)
          .with('worker.arp.representative_in_progress_form_cleaner.form_2_deleted', 1)

        subject.perform
      end
    end
  end
end
