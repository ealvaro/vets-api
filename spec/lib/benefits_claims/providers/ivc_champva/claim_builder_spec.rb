# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsClaims::Providers::IvcChampva::ClaimBuilder do
  describe '.claim_type_for' do
    it 'maps docs-only resubmission 10-10d form numbers to CHAMPVA application' do
      expect(described_class.claim_type_for('10-10D-EXTENDED-EXISTING')).to eq('CHAMPVA application')
      expect(described_class.claim_type_for('10-10D-EXTENDED-ENROLLMENT')).to eq('CHAMPVA application')
      expect(described_class.claim_type_for('10-10D-SUPPLEMENTAL-EXISTING')).to eq('CHAMPVA application')
      expect(described_class.claim_type_for('10-10D-SUPPLEMENTAL-ENROLLMENT')).to eq('CHAMPVA application')
    end
  end

  describe '.normalize_status' do
    it 'maps "Submission Received" to claimReceived' do
      expect(described_class.normalize_status('Submission Received')).to eq('claimReceived')
    end

    it 'maps "Received" to claimReceived' do
      expect(described_class.normalize_status('Received')).to eq('claimReceived')
    end

    it 'maps "Submitted" to claimReceived' do
      expect(described_class.normalize_status('Submitted')).to eq('claimReceived')
    end

    it 'maps processed statuses to vbms' do
      expect(described_class.normalize_status('Processed')).to eq('vbms')
      expect(described_class.normalize_status('Manually Processed')).to eq('vbms')
    end

    it 'maps error statuses to error' do
      expect(described_class.normalize_status('Not Processed')).to eq('error')
      expect(described_class.normalize_status('Failed')).to eq('error')
    end

    it 'maps additional documentation requested to claimReceived' do
      expect(described_class.normalize_status('additional documentation requested')).to eq('claimReceived')
    end

    it 'treats former Pega eligibility denial statuses as unrecognized (error) now that complete is applicant-driven' do
      [
        'eligiblity denied/additional information needed',
        'eligibility denied/additional information needed',
        'Eligible - issued a card'
      ].each do |status|
        expect(described_class.normalize_status(status)).to eq('error')
      end
    end

    it 'returns pending for blank status' do
      expect(described_class.normalize_status(nil)).to eq('pending')
      expect(described_class.normalize_status('')).to eq('pending')
    end

    it 'returns error for unrecognized statuses' do
      expect(described_class.normalize_status('Some Unknown Status')).to eq('error')
    end
  end

  describe 'IvcChampvaApplicant.all_resolved_for?' do
    let(:transaction_uuid) { SecureRandom.uuid }

    it 'returns true when all applicants have eligibility_resolved = true' do
      create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: true)
      create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: true)
      expect(IvcChampvaApplicant.all_resolved_for?(transaction_uuid)).to be(true)
    end

    it 'returns false when any applicant has eligibility_resolved = false' do
      create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: true)
      create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: false)
      expect(IvcChampvaApplicant.all_resolved_for?(transaction_uuid)).to be(false)
    end

    it 'returns false when no applicants exist for the transaction' do
      expect(IvcChampvaApplicant.all_resolved_for?(transaction_uuid)).to be(false)
    end

    it 'returns false when transaction_uuid is blank' do
      expect(IvcChampvaApplicant.all_resolved_for?(nil)).to be(false)
      expect(IvcChampvaApplicant.all_resolved_for?('')).to be(false)
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
        ['Screenshot 2026-04-21 at 9.22.07 AM.png', 'abc_vha_10_10d.pdf']
      )
    end

    it 'filters supporting_doc files regardless of form_number format' do
      created_at = Time.zone.parse('2026-05-11 11:00:00')
      supporting_doc_record = double(
        id: 301,
        form_number: '10-10D-EXTENDED',
        file_name: '2073cde3-789e-45f4-bad4-232f1a7cd966_vha_10_10d_supporting_doc-0.pdf',
        created_at:
      )
      normal_record = double(
        id: 302,
        form_number: '10-10D-EXTENDED',
        file_name: 'school_enrollment_certification_form.png',
        created_at:
      )

      supporting_documents = described_class.build_supporting_documents([supporting_doc_record, normal_record])

      expect(supporting_documents.map(&:original_file_name)).to eq(['school_enrollment_certification_form.png'])
    end
  end

  describe '.build_claim_status_meta' do
    let(:record) do
      double(
        first_name: 'Jane',
        last_name: 'Doe',
        request_json: {
          'applicants' => [
            { 'applicantName' => { 'first' => 'John', 'last' => 'Doe' } }
          ]
        },
        form_uuid: '123',
        form_number: '10-10D',
        file_name: 'test.pdf',
        pega_status: nil,
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      )
    end
    let(:user) { double('user', id: 1, first_name: 'John', last_name: 'Veteran') }

    context 'when cst_champva_custom_content flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, user).and_return(true) }

      it 'returns the base metadata hash with currentStatus injected' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        expect(meta).to be_a(Hash)
        expect(meta.dig('whatWeAreDoing', 'currentStatus')).to eq('pending')
      end

      it 'maps claimReceived status into currentStatus correctly' do
        meta = described_class.build_claim_status_meta([record], 'claimReceived', user)
        expect(meta.dig('whatWeAreDoing', 'currentStatus')).to eq('claimReceived')
      end

      it 'includes a statusMap entry for claimReceived' do
        meta = described_class.build_claim_status_meta([record], 'claimReceived', user)
        expect(meta.dig('whatWeAreDoing', 'statusMap', 'claimReceived')).to be_a(Hash)
        expect(meta.dig('whatWeAreDoing', 'statusMap', 'claimReceived', 'title')).to be_present
      end

      it 'maps claimReceived to step 1 in currentStepByStatus' do
        meta = described_class.build_claim_status_meta([record], 'claimReceived', user)
        expect(meta.dig('overview', 'currentStepByStatus', 'claimReceived')).to eq(1)
      end

      it 'maps vbms to step 2 in currentStepByStatus' do
        meta = described_class.build_claim_status_meta([record], 'vbms', user)
        expect(meta.dig('overview', 'currentStepByStatus', 'vbms')).to eq(2)
      end

      it 'injects veteran name into sectionGroups' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        section_groups = meta.dig('detail', 'sectionGroups')
        veteran_group = section_groups.find { |g| g['title'] == 'Veteran' }
        expect(veteran_group).to be_present
        expect(veteran_group['items']).to include('John Veteran')
      end

      it 'injects applicant names into sectionGroups' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        section_groups = meta.dig('detail', 'sectionGroups')
        applicant_group = section_groups.find { |g| g['title'] == 'Applicants' }
        expect(applicant_group).to be_present
        expect(applicant_group['items']).to include('John Doe')
      end

      it 'does not show veteran name in Applicants section group' do
        record_with_veteran_in_applicants = double(
          first_name: 'Jane',
          last_name: 'Doe',
          request_json: {
            'applicants' => [
              { 'applicantName' => { 'first' => 'John', 'last' => 'Veteran' } },
              { 'applicantName' => { 'first' => 'John', 'last' => 'Doe' } }
            ]
          },
          form_uuid: '456',
          form_number: '10-10D',
          file_name: 'test3.pdf',
          pega_status: nil,
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        )

        meta = described_class.build_claim_status_meta([record_with_veteran_in_applicants], 'pending', user)
        applicant_group = meta.dig('detail', 'sectionGroups').find { |g| g['title'] == 'Applicants' }
        expect(applicant_group['items']).to contain_exactly('John Doe')
      end

      it 'deduplicates applicant names across records with the same person' do
        duplicate_record = double(
          first_name: 'Jane',
          last_name: 'Doe',
          request_json: {
            'applicants' => [
              { 'applicantName' => { 'first' => 'John', 'last' => 'Doe' } }
            ]
          },
          form_uuid: '123',
          form_number: '10-10D',
          file_name: 'test2.pdf',
          pega_status: nil,
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        )
        meta = described_class.build_claim_status_meta([record, duplicate_record], 'pending', user)
        applicant_group = meta.dig('detail', 'sectionGroups').find { |g| g['title'] == 'Applicants' }
        expect(applicant_group['items'].count).to eq(1)
      end

      it 'falls back to record names when request_json has no applicants array' do
        record_without_applicants = double(
          first_name: 'Fallback',
          last_name: 'Name',
          request_json: {},
          form_uuid: '999',
          form_number: '10-10D',
          file_name: 'no-applicants.pdf',
          pega_status: nil,
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        )

        meta = described_class.build_claim_status_meta([record_without_applicants], 'pending', user)
        applicant_group = meta.dig('detail', 'sectionGroups').find { |g| g['title'] == 'Applicants' }
        expect(applicant_group['items']).to include('Fallback Name')
      end
    end

    context 'when cst_champva_custom_content flipper is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, user).and_return(false) }

      it 'returns nil' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        expect(meta).to be_nil
      end
    end
  end
end
