# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsClaims::Providers::IvcChampva::ClaimBuilder do
  describe '.claim_type_for' do
    it 'maps docs-only resubmission 10-10d form numbers to CHAMPVA application' do
      expect(described_class.claim_type_for('10-10D-EXTENDED-EXISTING')).to eq('CHAMPVA application')
      expect(described_class.claim_type_for('10-10D-EXTENDED-ENROLLMENT')).to eq('CHAMPVA application')
    end
  end

  describe '.build_supporting_documents' do
    it 'filters internal docs-only generated 10-10D files from user-facing supporting documents' do
      created_at = Time.zone.parse('2026-04-21 11:30:00')
      user_file_record = double(
        id: 101,
        form_number: '10-10D-EXTENDED-EXISTING',
        file_name: 'Screenshot 2026-04-21 at 9.22.07 AM.png',
        created_at:
      )
      internal_main_pdf_record = double(
        id: 102,
        form_number: '10-10D-EXTENDED-EXISTING',
        file_name: 'abc_vha_10_10d.pdf',
        created_at:
      )
      internal_supporting_pdf_record = double(
        id: 103,
        form_number: '10-10D-EXTENDED-EXISTING',
        file_name: 'abc_vha_10_10d_supporting_doc-0.pdf',
        created_at:
      )

      supporting_documents = described_class.build_supporting_documents(
        [user_file_record, internal_main_pdf_record, internal_supporting_pdf_record]
      )

      expect(supporting_documents.map(&:original_file_name)).to eq(
        ['Screenshot 2026-04-21 at 9.22.07 AM.png']
      )
    end
  end
end
