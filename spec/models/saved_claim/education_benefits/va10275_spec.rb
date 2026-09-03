# frozen_string_literal: true

require 'rails_helper'
require 'lib/saved_claims_spec_helper'

RSpec.describe SavedClaim::EducationBenefits::VA10275 do
  let(:instance) { build(:va10275) }

  it_behaves_like 'saved_claim'

  validate_inclusion(:form_id, '22-10275')

  describe 'retention_period' do
    it 'returns the correct period' do
      expect(instance.retention_period).to be_within(1.minute).of(60.days)
    end
  end

  describe '#to_pdf' do
    context 'when vsp_environment is production' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('production')
        allow(Rails.env).to receive_messages(development?: false, test?: false)
      end

      it 'falls back to the default to_pdf without extras_redesign options' do
        expect(PdfFill::Filler).to receive(:fill_form).with(instance, 'abc')

        instance.to_pdf('abc')
      end
    end

    context 'when vsp_environment is staging' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('staging')
        allow(Rails.env).to receive_messages(development?: false, test?: false)
      end

      it 'uses extras_redesign fill_options' do
        expect(PdfFill::Filler).to receive(:fill_form).with(
          instance, 'abc', hash_including(extras_redesign: true)
        )

        instance.to_pdf('abc')
      end
    end
  end

  describe '#after_submit' do
    let(:user) { create(:user) }

    before do
      allow(Flipper).to receive(:enabled?).and_call_original
    end

    describe 'confirmation email for 10275' do
      subject { create(:va10275) }

      before do
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
      end

      it 'sends the email via V2 QueueEmailJob' do
        subject.after_submit(user)

        expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
          'form_10275@example.com',
          'form10275_submission_email_template_id',
          satisfy do |args|
            args[:submission_id] == subject.id &&
            args[:agreement_type] == 'New commitment' &&
            args[:institution_details].include?('Springfield University') &&
            args[:institution_details].include?('US123456') &&
            args[:additional_locations].include?('Springfield Technical Institute') &&
            args[:additional_locations].include?('US654321') &&
            args[:points_of_contact].include?('michael.brown@springfield.edu') &&
            args[:points_of_contact].include?('emily.johnson@springfield.edu') &&
            args[:submission_information].include?('Robert Smith')
          end,
          'Settings.vanotify.services.va_gov.api_key',
          anything
        )
      end
    end
  end
end
