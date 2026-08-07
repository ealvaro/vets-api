# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA288832 do
  let(:profile) { described_class.new(form_id: '28-8832', user:) }

  let(:user) { create(:user, :loa3) }

  describe '.form_filename_and_version' do
    let(:form_id) { '28-8832' }

    context 'when v2 flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:chapter_36_form_rebuild_cveteam, user).and_return(false)
      end

      it 'returns legacy form id and version' do
        versioned_form_id, version_number = described_class.form_filename_and_version(form_id, user)

        expect(versioned_form_id).to eq('28-8832')
        expect(version_number).to eq(1)
      end
    end

    context 'when v2 flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:chapter_36_form_rebuild_cveteam, user).and_return(true)
      end

      it 'returns v2 form id and version' do
        versioned_form_id, version_number = described_class.form_filename_and_version(form_id, user)

        expect(versioned_form_id).to eq('28-8832v2')
        expect(version_number).to eq(2)
      end
    end
  end

  describe '#prefill' do
    before do
      allow(FormProfile).to receive(:prefill_enabled_forms).and_return(['28-8832'])
      allow(profile).to receive_messages(
        initialize_identity_information: {},
        initialize_military_information: {},
        initialize_contact_information: {},
        generate_prefill: { 'test' => 'value' }
      )
    end

    context 'when v2 flag is disabled' do
      before do
        allow(described_class).to receive(:form_filename_and_version).with('28-8832', user).and_return(['28-8832', 1])
        allow(described_class).to receive(:mappings_for_form).with('28-8832').and_return({})
      end

      it 'does not stamp a version when the legacy mapping is selected' do
        data = profile.prefill

        expect(data[:form_data]).to eq({ 'test' => 'value' })
        expect(data[:form_data]).not_to have_key('version')
      end
    end

    context 'when v2 flag is enabled' do
      before do
        allow(described_class).to receive(:form_filename_and_version).with('28-8832', user).and_return(['28-8832v2', 2])
        allow(described_class).to receive(:mappings_for_form).with('28-8832v2').and_return({})
      end

      it 'stamps version 2 when the v2 mapping is selected' do
        data = profile.prefill

        expect(data[:form_data]).to eq({ 'test' => 'value', 'version' => 2 })
      end
    end
  end
end
