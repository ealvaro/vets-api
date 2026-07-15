# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA2010206 do
  subject(:form_profile) { described_class.new(form_id: '20-10206', user:) }

  let(:user) { build(:user, :loa3, :legacy_icn) }

  describe '#metadata' do
    it 'returns prefill metadata for the preparer type page' do
      expect(form_profile.metadata).to eq(
        version: 0,
        prefill: true,
        returnUrl: '/preparer-type'
      )
    end
  end

  describe '#prefill' do
    it 'returns veteran SSN data for the frontend prefill transformer' do
      prefill = form_profile.prefill

      expect(prefill[:metadata]).to eq(form_profile.metadata)
      expect(prefill[:form_data]).to eq(
        'veteran' => {
          'ssn' => user.ssn
        }
      )
    end
  end

  describe '.prefill_enabled_forms' do
    it 'includes 20-10206 when vff_simple_forms prefill is enabled' do
      expect(FormProfile.prefill_enabled_forms).to include('20-10206')
    end

    it 'excludes 20-10206 when vff_simple_forms prefill is the string "false"' do
      allow(Settings.vff_simple_forms).to receive(:prefill).and_return('false')

      expect(FormProfile.prefill_enabled_forms).not_to include('20-10206')
    end

    it 'includes 20-10206 when vff_simple_forms prefill is the string "true"' do
      allow(Settings.vff_simple_forms).to receive(:prefill).and_return('true')

      expect(FormProfile.prefill_enabled_forms).to include('20-10206')
    end
  end
end
