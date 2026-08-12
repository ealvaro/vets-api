# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::ClaimsAttachmentIds do
  let(:base_form_data) do
    {
      'form_number' => '10-7959A',
      'claims' => [{ 'provider_name' => 'Test Provider' }],
      'supporting_docs' => [
        { 'confirmation_code' => 'code1', 'attachment_id' => 'Medical Records' },
        { 'confirmation_code' => 'code2', 'attachment_id' => 'EOB' }
      ]
    }
  end
  let(:form) { IvcChampva::VHA107959a.new(base_form_data) }

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
  end

  describe '#build_attachment_ids' do
    context 'when DTA applies' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
      end

      it 'overrides PDI resubmission logic with DTA attachment IDs' do
        dta_data = base_form_data.merge(
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'PDI number',
          'has_claim_docs' => false
        )
        dta_form = IvcChampva::VHA107959a.new(dta_data)

        result = dta_form.build_attachment_ids('vha_10_7959a', 1)

        expect(result).to eq(['Duty to Assist', 'Duty to Assist', 'Duty to Assist'])
      end

      it 'overrides Control number resubmission logic with DTA attachment IDs' do
        dta_data = base_form_data.merge(
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'Control number',
          'has_claim_docs' => false
        )
        dta_form = IvcChampva::VHA107959a.new(dta_data)

        record = double('Record', created_at: Time.zone.now, file: double(id: 'file1'))
        allow(PersistentAttachments::MilitaryRecords).to receive(:find_by).and_return(record)

        result = dta_form.build_attachment_ids('vha_10_7959a', 1)

        expect(result).to eq(['Duty to Assist', 'Duty to Assist', 'Duty to Assist'])
      end
    end

    context 'when DTA does not apply (has_claim_docs is true)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
      end

      it 'uses PDI resubmission logic when PDI number selected' do
        pdi_data = base_form_data.merge(
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'PDI number',
          'has_claim_docs' => true
        )
        pdi_form = IvcChampva::VHA107959a.new(pdi_data)

        result = pdi_form.build_attachment_ids('vha_10_7959a', 1)

        expect(result).to eq(['CVA Bene Response', 'CVA Bene Response', 'CVA Bene Response'])
      end

      it 'uses Control number resubmission logic when Control number selected' do
        control_data = base_form_data.merge(
          'claim_status' => 'resubmission',
          'pdi_or_claim_number' => 'Control number',
          'has_claim_docs' => true
        )
        control_form = IvcChampva::VHA107959a.new(control_data)

        record = double('Record', created_at: Time.zone.now, file: double(id: 'file1'))
        allow(PersistentAttachments::MilitaryRecords).to receive(:find_by).and_return(record)

        result = control_form.build_attachment_ids('vha_10_7959a', 1)

        expect(result).to eq(['CVA Reopen', 'Medical Records', 'EOB'])
      end
    end
  end

  describe '#build_pdi_resubmission_attachment_ids (private)' do
    it 'labels all documents as CVA Bene Response' do
      result = form.send(:build_pdi_resubmission_attachment_ids, 1)

      expect(result).to eq(['CVA Bene Response', 'CVA Bene Response', 'CVA Bene Response'])
    end

    it 'handles submissions with no supporting docs' do
      no_docs_form = IvcChampva::VHA107959a.new({ 'supporting_docs' => nil })
      result = no_docs_form.send(:build_pdi_resubmission_attachment_ids, 1)

      expect(result).to eq(['CVA Bene Response'])
    end

    it 'handles multiple main form pages' do
      one_doc_form = IvcChampva::VHA107959a.new(
        'supporting_docs' => [
          { 'confirmation_code' => 'code1', 'attachment_id' => 'Medical Records' }
        ]
      )

      result = one_doc_form.send(:build_pdi_resubmission_attachment_ids, 2)

      expect(result).to eq(['CVA Bene Response', 'CVA Bene Response', 'CVA Bene Response'])
    end
  end

  describe '#dta_applies? (private)' do
    it 'returns true when all conditions are met' do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)

      dta_form = IvcChampva::VHA107959a.new(
        'claim_status' => 'resubmission', 'has_claim_docs' => false
      )
      result = dta_form.send(:dta_applies?)

      expect(result).to be true
    end

    it 'returns false when feature flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(false)

      dta_form = IvcChampva::VHA107959a.new(
        'claim_status' => 'resubmission', 'has_claim_docs' => false
      )
      result = dta_form.send(:dta_applies?)

      expect(result).to be false
    end

    it 'returns false when claim_status is not resubmission' do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)

      non_resub_form = IvcChampva::VHA107959a.new(
        'claim_status' => 'new', 'has_claim_docs' => false
      )
      result = non_resub_form.send(:dta_applies?)

      expect(result).to be false
    end

    it 'returns false when has_claim_docs is true' do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)

      has_docs_form = IvcChampva::VHA107959a.new(
        'claim_status' => 'resubmission', 'has_claim_docs' => true
      )
      result = has_docs_form.send(:dta_applies?)

      expect(result).to be false
    end
  end

  describe 'works with VHA107959a2027 form class' do
    let(:form2027) { IvcChampva::VHA107959a2027.new(base_form_data) }

    before do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
    end

    it 'uses the same DTA logic as VHA107959a' do
      dta_data = base_form_data.merge(
        'claim_status' => 'resubmission',
        'has_claim_docs' => false
      )
      dta_form = IvcChampva::VHA107959a2027.new(dta_data)

      result = dta_form.build_attachment_ids('vha_10_7959a', 1)

      expect(result).to eq(['Duty to Assist', 'Duty to Assist', 'Duty to Assist'])
    end
  end
end
