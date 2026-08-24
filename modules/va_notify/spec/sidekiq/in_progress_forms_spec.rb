# frozen_string_literal: true

require 'rails_helper'

describe VANotify::InProgressForms, type: :worker do
  describe '#perform' do
    context 'when va_notify_in_progress_forms_stagger is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:va_notify_in_progress_forms_stagger).and_return(true) }

      it 'enqueues a reminder only for forms within the eligibility window' do
        eligible_form = create_in_progress_form_days_ago(7, user_uuid: create(:user, uuid: SecureRandom.uuid).uuid,
                                                            form_id: '686C-674')
        ineligible_form = create_in_progress_form_days_ago(21, user_uuid: create(:user, uuid: SecureRandom.uuid).uuid,
                                                               form_id: '686C-674')

        expect(VANotify::InProgressFormReminder).to receive(:perform_in).with(anything, eligible_form.id)
        expect(VANotify::InProgressFormReminder).not_to receive(:perform_in).with(anything, ineligible_form.id)

        VANotify::InProgressForms.new.perform
      end

      it 'staggers the reminders evenly across the spread window' do
        ids = [10, 20, 30, 40]
        finder = instance_double(VANotify::FindInProgressForms, to_notify: ids)
        allow(VANotify::FindInProgressForms).to receive(:new).and_return(finder)

        step = VANotify::InProgressForms::SPREAD_WINDOW.to_f / ids.size
        ids.each_with_index do |id, index|
          expect(VANotify::InProgressFormReminder).to receive(:perform_in).with((step * index).seconds, id)
        end

        VANotify::InProgressForms.new.perform
      end

      it 'does nothing when there are no forms to notify' do
        finder = instance_double(VANotify::FindInProgressForms, to_notify: [])
        allow(VANotify::FindInProgressForms).to receive(:new).and_return(finder)

        expect(VANotify::InProgressFormReminder).not_to receive(:perform_in)

        VANotify::InProgressForms.new.perform
      end
    end

    context 'when va_notify_in_progress_forms_stagger is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:va_notify_in_progress_forms_stagger).and_return(false) }

      it 'enqueues a reminder immediately only for forms within the eligibility window' do
        eligible_form = create_in_progress_form_days_ago(7, user_uuid: create(:user, uuid: SecureRandom.uuid).uuid,
                                                            form_id: '686C-674')
        ineligible_form = create_in_progress_form_days_ago(21, user_uuid: create(:user, uuid: SecureRandom.uuid).uuid,
                                                               form_id: '686C-674')

        expect(VANotify::InProgressFormReminder).to receive(:perform_async).with(eligible_form.id)
        expect(VANotify::InProgressFormReminder).not_to receive(:perform_async).with(ineligible_form.id)

        VANotify::InProgressForms.new.perform
      end

      it 'enqueues all reminders immediately without staggering' do
        ids = [10, 20, 30, 40]
        finder = instance_double(VANotify::FindInProgressForms, to_notify: ids)
        allow(VANotify::FindInProgressForms).to receive(:new).and_return(finder)

        ids.each do |id|
          expect(VANotify::InProgressFormReminder).to receive(:perform_async).with(id)
        end
        expect(VANotify::InProgressFormReminder).not_to receive(:perform_in)

        VANotify::InProgressForms.new.perform
      end

      it 'does nothing when there are no forms to notify' do
        finder = instance_double(VANotify::FindInProgressForms, to_notify: [])
        allow(VANotify::FindInProgressForms).to receive(:new).and_return(finder)

        expect(VANotify::InProgressFormReminder).not_to receive(:perform_async)

        VANotify::InProgressForms.new.perform
      end
    end
  end

  def create_in_progress_form_days_ago(count, user_uuid:, form_id:)
    Timecop.freeze(count.days.ago)
    in_progress_form = create(:in_progress_form, user_uuid:, form_id:)
    Timecop.return
    in_progress_form
  end
end
