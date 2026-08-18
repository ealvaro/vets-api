# frozen_string_literal: true

require 'rails_helper'
require 'debts_api/v0/fsr_form_builder'
require 'debts_api/v0/vha_fsr_form'
RSpec.describe DebtsApi::V0::VbaFsrForm, type: :service do
  describe 'zero income notice' do
    let(:combined_form_data) { get_fixture_absolute('modules/debts_api/spec/fixtures/fsr_forms/combined_fsr_form') }
    let(:user) { build(:user, :loa3) }
    let(:builder) { DebtsApi::V0::FsrFormBuilder.new(form_data, '123', user) }

    context 'when zeroIncomeSeen is set' do
      let(:form_data) { combined_form_data.merge(DebtsApi::V0::FsrFormBuilder::ZERO_INCOME_KEY => true) }

      it 'appends the notice to the DMC form only' do
        expect(builder.vba_form.form_data['additionalData']['additionalComments'])
          .to include(DebtsApi::V0::FsrForm::ZERO_INCOME_COMMENT)
        expect(builder.vha_forms.first.form_data['additionalData']['additionalComments'])
          .not_to include(DebtsApi::V0::FsrForm::ZERO_INCOME_COMMENT)
      end

      it 'does not send the flag itself to DMC' do
        expect(builder.vba_form.form_data).not_to have_key('zeroIncomeSeen')
      end
    end

    context 'when zeroIncomeSeen is absent' do
      let(:form_data) { combined_form_data }

      it 'leaves additionalComments alone' do
        expect(builder.vba_form.form_data['additionalData']['additionalComments'])
          .not_to include(DebtsApi::V0::FsrForm::ZERO_INCOME_COMMENT)
      end
    end
  end

  describe '#persist_form_submission' do
    let(:combined_form_data) { get_fixture_absolute('modules/debts_api/spec/fixtures/fsr_forms/combined_fsr_form') }
    let(:vba_form_data) { get_fixture_absolute('modules/debts_api/spec/fixtures/fsr_forms/vba_fsr_form') }
    let(:vha_form_data) { get_fixture_absolute('modules/debts_api/spec/fixtures/fsr_forms/vha_fsr_form') }
    let(:user) { build(:user, :loa3) }
    let(:user_data) { build(:user_profile_attributes) }

    context 'given an InProgressForm can be found' do
      let(:builder) { DebtsApi::V0::FsrFormBuilder.new(combined_form_data, '123', user) }
      let(:in_progress_form) { create(:in_progress_5655_form, user_uuid: user.uuid) }

      it 'saves ipf data' do
        in_progress_form
        vba_form = builder.vba_form
        submission = vba_form.persist_form_submission
        expect(submission.ipf_data).to eq(in_progress_form.form_data)
      end
    end

    context 'given an InProgressForm can not be found' do
      let(:builder) { DebtsApi::V0::FsrFormBuilder.new(combined_form_data, '123', user) }

      it 'leaves ipf data nil' do
        vha_form = builder.vha_forms.first
        submission = vha_form.persist_form_submission
        expect(submission.ipf_data).to be_nil
      end
    end
  end
end
