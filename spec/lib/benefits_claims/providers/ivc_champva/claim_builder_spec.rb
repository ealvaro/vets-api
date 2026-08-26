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

  describe '.status_for' do
    it 'returns claimReceived when applicants are not yet resolved' do
      expect(described_class.status_for(false)).to eq('claimReceived')
    end

    it 'returns complete when every applicant has been resolved' do
      expect(described_class.status_for(true)).to eq('complete')
    end
  end

  describe '.build_claim_response' do
    let(:user) { double('user', id: 1, first_name: 'John', last_name: 'Veteran') }

    before do
      allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:ivc_champva_ves_eligibility_on_demand, user).and_return(true)
    end

    describe 'Step 1 "Moved to this step" date (ticket #152150)' do
      it 'uses the earliest created_at across every form record, not the representative\'s updated_at' do
        # pick_representative picks max_by(&:updated_at) -- give the LATER-created record the
        # LATER updated_at too, so it's the representative, then confirm phase_change_date still
        # comes from the EARLIER record's created_at, not the representative's updated_at.
        older = create(:ivc_champva_form, created_at: 3.days.ago, updated_at: 3.days.ago)
        representative = create(:ivc_champva_form,
                                form_uuid: older.form_uuid, transaction_uuid: older.transaction_uuid,
                                created_at: 1.day.ago, updated_at: 1.hour.ago)

        response = described_class.build_claim_response([older, representative])

        expect(response.claim_phase_dates.phase_change_date).to eq(older.created_at.to_date.iso8601)
        expect(response.claim_phase_dates.phase_change_date).not_to eq(representative.updated_at.to_date.iso8601)
      end

      it 'does not change when a form record is updated after submission' do
        form = create(:ivc_champva_form, created_at: 5.days.ago, updated_at: 5.days.ago)

        original = described_class.build_claim_response([form])

        # Simulates a later, unrelated update to the record (e.g. a Pega status callback) --
        # bumps updated_at without touching created_at.
        form.update!(pega_status: 'Processed')
        expect(form.updated_at).not_to eq(form.created_at)

        after_update = described_class.build_claim_response([form.reload])

        expect(after_update.claim_phase_dates.phase_change_date)
          .to eq(original.claim_phase_dates.phase_change_date)
        expect(after_update.claim_phase_dates.phase_change_date).to eq(form.created_at.to_date.iso8601)
      end

      it 'matches claim_date, so "Received on" and "Moved to this step on" always represent ' \
         'the same date' do
        form = create(:ivc_champva_form, created_at: 2.days.ago, updated_at: 1.hour.ago)

        response = described_class.build_claim_response([form])

        expect(response.claim_phase_dates.phase_change_date).to eq(response.claim_date)
      end
    end

    describe 'Step 2 "Moved to this step" date (unchanged by ticket #152150 -- out of scope)' do
      it 'still uses the representative\'s updated_at once the application is decided' do
        transaction_uuid = SecureRandom.uuid
        form = create(:ivc_champva_form, transaction_uuid:, created_at: 10.days.ago, updated_at: 1.day.ago)
        create(:ivc_champva_applicant, transaction_uuid:, eligibility_resolved: true)

        response = described_class.build_claim_response([form])

        expect(response.status).to eq('complete')
        expect(response.claim_phase_dates.phase_change_date).to eq(form.updated_at.to_date.iso8601)
        expect(response.claim_phase_dates.phase_change_date).not_to eq(form.created_at.to_date.iso8601)
      end
    end

    context 'when a file upload has inserted a newer IvcChampvaForm row with no transaction_uuid' do
      # Regression coverage for a reported bug: application decision cards
      # vanished after uploading a file on the Files tab and navigating back to
      # Status, until a hard refresh.
      it 'still returns cst_champva_applicants and application_decided from the resolved transaction' do
        form_uuid = SecureRandom.uuid
        resolved_transaction_uuid = SecureRandom.uuid

        original_form = create(
          :ivc_champva_form,
          form_uuid:,
          transaction_uuid: resolved_transaction_uuid,
          updated_at: 1.hour.ago
        )
        create(
          :ivc_champva_applicant,
          transaction_uuid: resolved_transaction_uuid,
          applicant_first_name: 'Jane',
          applicant_last_name: 'Smith',
          eligibility_resolved: true,
          ves_eligibility_status: 'ELIGIBLE'
        )

        # Simulates the new IvcChampvaForm row inserted by a Files-tab upload:
        # same claim (form_uuid), no transaction_uuid, more recently updated.
        upload_form = create(
          :ivc_champva_form,
          form_uuid:,
          transaction_uuid: nil,
          updated_at: Time.current
        )

        dto = described_class.build_claim_response([original_form, upload_form], user)

        expect(dto.cst_champva_applicants).not_to be_empty
        expect(dto.application_decided).to be(true)
      end

      it 'still reflects complete status and a close_date rather than reverting to claimReceived' do
        form_uuid = SecureRandom.uuid
        resolved_transaction_uuid = SecureRandom.uuid

        original_form = create(
          :ivc_champva_form,
          form_uuid:,
          transaction_uuid: resolved_transaction_uuid,
          updated_at: 1.hour.ago
        )
        create(
          :ivc_champva_applicant,
          transaction_uuid: resolved_transaction_uuid,
          eligibility_resolved: true,
          ves_eligibility_status: 'ELIGIBLE'
        )
        upload_form = create(
          :ivc_champva_form,
          form_uuid:,
          transaction_uuid: nil,
          updated_at: Time.current
        )

        dto = described_class.build_claim_response([original_form, upload_form], user)

        expect(dto.status).to eq('complete')
        expect(dto.close_date).not_to be_nil
        expect(dto.decision_letter_sent).to be(true)
      end

      it 'returns the applicant data when the original (non-blank) transaction_uuid row is representative' do
        form_uuid = SecureRandom.uuid
        resolved_transaction_uuid = SecureRandom.uuid

        original_form = create(
          :ivc_champva_form,
          form_uuid:,
          transaction_uuid: resolved_transaction_uuid,
          updated_at: Time.current
        )
        create(
          :ivc_champva_applicant,
          transaction_uuid: resolved_transaction_uuid,
          applicant_first_name: 'Jane',
          applicant_last_name: 'Smith',
          eligibility_resolved: true,
          ves_eligibility_status: 'ELIGIBLE'
        )

        dto = described_class.build_claim_response([original_form], user)

        expect(dto.cst_champva_applicants).not_to be_empty
        expect(dto.application_decided).to be(true)
      end

      it 'still returns empty/nil eligibility data when no row for the form_uuid carries a transaction_uuid' do
        form_uuid = SecureRandom.uuid
        upload_form = create(:ivc_champva_form, form_uuid:, transaction_uuid: nil)

        dto = described_class.build_claim_response([upload_form], user)

        expect(dto.cst_champva_applicants).to eq([])
        expect(dto.application_decided).to be_nil
      end
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
        transaction_uuid: nil,
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      )
    end
    let(:user) { double('user', id: 1, first_name: 'John', last_name: 'Veteran') }

    context 'when cst_champva_custom_content flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, user).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:ivc_champva_ves_eligibility_on_demand, user).and_return(false)
      end

      it 'returns the base metadata hash with currentStatus injected' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        expect(meta).to be_a(Hash)
        expect(meta.dig('whatWeAreDoing', 'currentStatus')).to eq('pending')
      end

      it 'does not include the raw repeatIneligibilityAlert config template — the real, ' \
         'name-substituted alert is only ever exposed at the response root' do
        meta = described_class.build_claim_status_meta([record], 'pending', user)
        expect(meta).not_to have_key('repeatIneligibilityAlert')
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
          transaction_uuid: nil,
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
          transaction_uuid: nil,
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
          transaction_uuid: nil,
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

    it 'does not include applicants or sponsor data (that lives at the response root instead)' do
      allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, user).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:ivc_champva_ves_eligibility_on_demand, user).and_return(true)

      meta = described_class.build_claim_status_meta([record], 'pending', user)
      expect(meta).not_to have_key('applicants')
      expect(meta).not_to have_key('sponsor')
    end
  end

  describe '.champva_eligibility_summary' do
    let(:transaction_uuid) { SecureRandom.uuid }
    let(:user) { double('user', id: 1) }

    context 'when ivc_champva_ves_eligibility_on_demand is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:ivc_champva_ves_eligibility_on_demand, user).and_return(false)
      end

      it 'returns empty/nil defaults' do
        expect(described_class.champva_eligibility_summary(transaction_uuid, user)).to eq(
          applicants: [],
          sponsor: nil,
          decided: nil,
          ves_date: nil,
          repeat_ineligibility_alert: nil,
          latest_update_date: nil
        )
      end
    end

    context 'when ivc_champva_ves_eligibility_on_demand is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:ivc_champva_ves_eligibility_on_demand, user).and_return(true)
      end

      it "includes each applicant's officially sent, allowlisted letters, oldest first" do
        applicant = IvcChampvaApplicant.create!(
          transaction_uuid:,
          applicant_icn: '1013836784V369083',
          person_type: 'BENEFICIARY'
        )
        applicant.ivc_champva_letters.create!(
          form_number: 'CG-A01a', letter_name: 'Welcome Letter', mail_status: 'MAILED_BY_PRINT_VENDOR',
          mail_status_date: Time.zone.parse('2026-07-20T00:00:00Z')
        )
        applicant.ivc_champva_letters.create!(
          form_number: 'CCL-A43a.ENC', letter_name: 'Acceptance Letter', mail_status: 'MAILED_BY_PRINT_VENDOR',
          mail_status_date: Time.zone.parse('2026-01-09T22:55:57Z')
        )

        applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]

        expect(applicants.first['letters']).to eq(
          [
            {
              'formNumber' => 'CCL-A43a.ENC',
              'letterName' => 'Acceptance Letter',
              'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
              'mailStatusDate' => '2026-01-09T22:55:57Z'
            },
            {
              'formNumber' => 'CG-A01a',
              'letterName' => 'Welcome Letter',
              'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
              'mailStatusDate' => '2026-07-20T00:00:00Z'
            }
          ]
        )
      end

      it 'excludes a letter that is not on the CHAMPVA letter allowlist, and one that has not ' \
         'actually been sent yet' do
        applicant = IvcChampvaApplicant.create!(
          transaction_uuid:,
          applicant_icn: '1013836784V369083',
          person_type: 'BENEFICIARY'
        )
        applicant.ivc_champva_letters.create!(
          form_number: 'NEW-001', letter_name: 'Unrelated Correspondence', mail_status: 'MAILED_BY_PRINT_VENDOR',
          mail_status_date: Time.zone.parse('2026-07-20T00:00:00Z')
        )
        applicant.ivc_champva_letters.create!(
          form_number: 'CCL-A43a.ENC', letter_name: 'Acceptance Letter', mail_status: 'PENDING',
          mail_status_date: Time.zone.parse('2026-01-09T22:55:57Z')
        )

        applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]

        expect(applicants.first['letters']).to eq([])
      end

      it 'includes personType and documentsRequested on each applicant, plus the sponsor' do
        IvcChampvaApplicant.create!(
          transaction_uuid:,
          applicant_icn: '1013836784V369083',
          applicant_first_name: 'Jane',
          applicant_last_name: 'Smith',
          person_type: 'BENEFICIARY',
          ves_eligibility_status: 'ELIGIBLE',
          documents_requested: true
        )
        IvcChampvaSponsor.create!(transaction_uuid:, first_name: 'John', last_name: 'Smith')

        summary = described_class.champva_eligibility_summary(transaction_uuid, user)
        applicants = summary[:applicants]
        sponsor = summary[:sponsor]

        expect(applicants.first).to include(
          'firstName' => 'Jane',
          'personType' => 'BENEFICIARY',
          'documentsRequested' => true
        )
        expect(sponsor).to include('firstName' => 'John', 'lastName' => 'Smith')
      end

      it 'marks the application decided only once every applicant is eligibility_resolved' do
        IvcChampvaApplicant.create!(transaction_uuid:, applicant_icn: '1', person_type: 'BENEFICIARY',
                                    eligibility_resolved: true, ves_status_updated_date: Date.new(2026, 7, 1))

        summary = described_class.champva_eligibility_summary(transaction_uuid, user)
        expect(summary[:decided]).to be(true)
        expect(summary[:ves_date]).to eq('2026-07-01')
      end

      it 'returns applicant hashes with the expected keys' do
        IvcChampvaApplicant.create!(
          transaction_uuid:,
          applicant_icn: '1013836784V369083',
          applicant_first_name: 'Jane',
          applicant_last_name: 'Smith',
          person_type: 'BENEFICIARY',
          ves_eligibility_status: 'ELIGIBLE',
          ves_eligibility_reason: 'No current school letter'
        )

        applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
        expect(applicants.length).to eq(1)
        expect(applicants.first).to eq(
          'firstName' => 'Jane',
          'lastName' => 'Smith',
          'personType' => 'BENEFICIARY',
          'vesEligibilityStatus' => 'ELIGIBLE',
          'vesEligibilityReason' => "Jane's not eligible for CHAMPVA benefits because they’re age 18 or older " \
                                    "and no current proof of school enrollment is on file.\n\nWe mailed Jane a " \
                                    'letter that has more information about our decision. It should arrive ' \
                                    'within 10 business days.',
          'vesEligibilityReasonLink' => nil,
          'documentsRequested' => false,
          'vesStatusUpdatedDate' => nil,
          'letters' => [],
          'hasRepeatIneligibilityLetter' => false,
          'repeatIneligibilityLetterDate' => nil
        )
      end

      it 'translates known VES reason codes and substitutes the applicant name' do
        IvcChampvaApplicant.create!(
          transaction_uuid:,
          applicant_icn: '1013836784V369083',
          applicant_first_name: 'Jane',
          person_type: 'SPONSOR',
          ves_eligibility_reason: 'child married'
        )

        applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
        expect(applicants.first['vesEligibilityReason']).to start_with("Jane's not eligible for CHAMPVA benefits")
      end

      describe 'hasRepeatIneligibilityLetter' do
        def create_applicant(icn, status:, status_updated_date: Date.new(2026, 1, 1), eligibility_resolved: true)
          IvcChampvaApplicant.create!(
            transaction_uuid:,
            applicant_icn: icn,
            person_type: 'BENEFICIARY',
            eligibility_resolved:,
            ves_eligibility_status: status,
            ves_status_updated_date: status_updated_date
          )
        end

        def add_letter(applicant, mail_status_date:, mail_status: 'MAILED_BY_PRINT_VENDOR')
          applicant.ivc_champva_letters.create!(
            form_number: 'CCL-A43a.ENC', mail_status:, mail_status_date: Time.zone.parse(mail_status_date)
          )
        end

        it 'is false for an enrolled (eligible) applicant, even with two sent letters' do
          applicant = create_applicant('1', status: 'ELIGIBLE')
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status_date: '2026-06-01')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => false,
            'repeatIneligibilityLetterDate' => nil
          )
        end

        it 'is false for a not-enrolled applicant with only their initial decision letter' do
          applicant = create_applicant('2', status: 'INELIGIBLE')
          add_letter(applicant, mail_status_date: '2026-01-03')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => false,
            'repeatIneligibilityLetterDate' => nil
          )
        end

        it 'is true once a not-enrolled applicant has received a second sent letter' do
          applicant = create_applicant('3', status: 'INELIGIBLE')
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status_date: '2026-06-15T12:00:00Z')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => true,
            'repeatIneligibilityLetterDate' => '2026-06-15T12:00:00Z'
          )
        end

        it 'populates the response-root repeatIneligibilityAlert with the applicant name substituted, ' \
           'only once true' do
          applicant = create_applicant('3b', status: 'INELIGIBLE')
          applicant.update!(applicant_first_name: 'Jane')
          add_letter(applicant, mail_status_date: '2026-01-03')

          alert = described_class.champva_eligibility_summary(
            transaction_uuid, user
          )[:repeat_ineligibility_alert]
          expect(alert).to be_nil

          add_letter(applicant, mail_status_date: '2026-06-15T12:00:00Z')
          alert = described_class.champva_eligibility_summary(
            transaction_uuid, user
          )[:repeat_ineligibility_alert]
          expect(alert['title']).to include('Jane')
          expect(alert['title']).not_to include('[Name]')
          expect(alert['description']).to include('Jane')
          expect(alert['description']).not_to include('[Name]')
        end

        it 'returns nil (not a hash of blank strings) when the alert config template fails to load, ' \
           'even with a flagged applicant' do
          applicant = create_applicant('3d', status: 'INELIGIBLE')
          applicant.update!(applicant_first_name: 'Jane')
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status_date: '2026-06-15T12:00:00Z')

          allow(BenefitsClaims::ClaimStatusMeta::ConfigLoader).to receive(:load)
            .with(provider: :ivc_champva, variant: 'repeat_ineligibility_alert')
            .and_raise(ArgumentError, 'config file not found')

          alert = described_class.champva_eligibility_summary(
            transaction_uuid, user
          )[:repeat_ineligibility_alert]

          expect(alert).to be_nil
        end

        it 'leaves vesEligibilityReason as the normal plain-language reason once ' \
           'hasRepeatIneligibilityLetter is true — repeat activity is surfaced only via the ' \
           'response-root repeatIneligibilityAlert, not by overriding the card body' do
          applicant = create_applicant('3c', status: 'INELIGIBLE')
          applicant.update!(applicant_first_name: 'Jane', ves_eligibility_reason: 'child married')
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status_date: '2026-06-15T12:00:00Z')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first['hasRepeatIneligibilityLetter']).to be(true)
          expect(applicants.first['vesEligibilityReason']).to start_with("Jane's not eligible for CHAMPVA benefits")
        end

        it 'ignores letters whose mail status is not in the sent-letter allowlist' do
          applicant = create_applicant('4', status: 'INELIGIBLE')
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status: 'PENDING_PRINT', mail_status_date: '2026-06-15')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => false,
            'repeatIneligibilityLetterDate' => nil
          )
        end

        it 'falls back to false when eligibility has not yet been resolved' do
          applicant = create_applicant('5', status: 'INELIGIBLE', eligibility_resolved: false)
          add_letter(applicant, mail_status_date: '2026-01-03')
          add_letter(applicant, mail_status_date: '2026-06-15')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => false,
            'repeatIneligibilityLetterDate' => nil
          )
        end

        it 'falls back to false when the not-enrolled applicant has no letters at all' do
          create_applicant('6', status: 'INELIGIBLE')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.first).to include(
            'hasRepeatIneligibilityLetter' => false,
            'repeatIneligibilityLetterDate' => nil
          )
        end

        it 'only flags the not-enrolled applicant with a second sent letter in a multi-applicant transaction' do
          enrolled = create_applicant('7', status: 'ELIGIBLE')
          add_letter(enrolled, mail_status_date: '2026-01-03')

          not_enrolled = create_applicant('8', status: 'INELIGIBLE')
          add_letter(not_enrolled, mail_status_date: '2026-01-03')
          add_letter(not_enrolled, mail_status_date: '2026-06-15')

          applicants = described_class.champva_eligibility_summary(transaction_uuid, user)[:applicants]
          expect(applicants.find { |a| a['vesEligibilityStatus'] == 'ELIGIBLE' })
            .to include('hasRepeatIneligibilityLetter' => false)
          expect(applicants.find { |a| a['vesEligibilityStatus'] == 'INELIGIBLE' })
            .to include('hasRepeatIneligibilityLetter' => true)
        end

        it 'names every flagged applicant (not just one) in a single response-root repeatIneligibilityAlert, ' \
           'not duplicated per applicant' do
          jane = create_applicant('9', status: 'INELIGIBLE')
          jane.update!(applicant_first_name: 'Jane')
          add_letter(jane, mail_status_date: '2026-01-03')
          add_letter(jane, mail_status_date: '2026-06-15')

          john = create_applicant('10', status: 'INELIGIBLE')
          john.update!(applicant_first_name: 'John')
          add_letter(john, mail_status_date: '2026-01-04')
          add_letter(john, mail_status_date: '2026-06-16')

          summary = described_class.champva_eligibility_summary(transaction_uuid, user)
          applicants = summary[:applicants]
          alert = summary[:repeat_ineligibility_alert]

          expect(alert['title']).to include('Jane and John')
          applicants.each { |a| expect(a).not_to have_key('repeatIneligibilityAlert') }
        end

        it 'names a flagged applicant once per distinct record, even when two flagged applicants ' \
           'share the same first name (never silently drops one via string-level dedup)' do
          jane1 = create_applicant('9c', status: 'INELIGIBLE')
          jane1.update!(applicant_first_name: 'Jane')
          add_letter(jane1, mail_status_date: '2026-01-03')
          add_letter(jane1, mail_status_date: '2026-06-15')

          jane2 = create_applicant('9d', status: 'INELIGIBLE')
          jane2.update!(applicant_first_name: 'Jane')
          add_letter(jane2, mail_status_date: '2026-01-04')
          add_letter(jane2, mail_status_date: '2026-06-16')

          summary = described_class.champva_eligibility_summary(transaction_uuid, user)
          applicants = summary[:applicants]
          alert = summary[:repeat_ineligibility_alert]

          expect(alert['title']).to include('Jane and Jane')
          expect(applicants.count { |a| a['hasRepeatIneligibilityLetter'] }).to eq(2)
        end

        it 'uses comma-separated, Oxford-comma grammar once three or more applicants are ' \
           'flagged (not just "and"-joining every name)' do
          jane = create_applicant('9b', status: 'INELIGIBLE')
          jane.update!(applicant_first_name: 'Jane')
          add_letter(jane, mail_status_date: '2026-01-03')
          add_letter(jane, mail_status_date: '2026-06-15')

          john = create_applicant('10b', status: 'INELIGIBLE')
          john.update!(applicant_first_name: 'John')
          add_letter(john, mail_status_date: '2026-01-04')
          add_letter(john, mail_status_date: '2026-06-16')

          sam = create_applicant('10c', status: 'INELIGIBLE')
          sam.update!(applicant_first_name: 'Sam')
          add_letter(sam, mail_status_date: '2026-01-05')
          add_letter(sam, mail_status_date: '2026-06-17')

          alert = described_class.champva_eligibility_summary(
            transaction_uuid, user
          )[:repeat_ineligibility_alert]

          expect(alert['title']).to include("Jane, John, and Sam's eligibility")
          expect(alert['description']).to start_with('Jane, John, and Sam is still not eligible')
        end

        it 'omits an unaffected applicant\'s name from the shared alert even when a sibling applicant is flagged' do
          jane = create_applicant('11', status: 'INELIGIBLE')
          jane.update!(applicant_first_name: 'Jane')
          add_letter(jane, mail_status_date: '2026-01-03')
          add_letter(jane, mail_status_date: '2026-06-15')

          unaffected = create_applicant('12', status: 'INELIGIBLE')
          unaffected.update!(applicant_first_name: 'Unaffected')
          add_letter(unaffected, mail_status_date: '2026-01-04')

          alert = described_class.champva_eligibility_summary(
            transaction_uuid, user
          )[:repeat_ineligibility_alert]

          expect(alert['title']).to include('Jane')
          expect(alert['title']).not_to include('Unaffected')
        end

        it 'excludes a sibling applicant whose VES eligibility check has not resolved yet from the shared alert ' \
           '(async per-applicant resolution)' do
          jane = create_applicant('13', status: 'INELIGIBLE')
          jane.update!(applicant_first_name: 'Jane')
          add_letter(jane, mail_status_date: '2026-01-03')
          add_letter(jane, mail_status_date: '2026-06-15')

          # Simulates ChampvaEligibilityService#sync_applicant_eligibility having succeeded for
          # Jane but still being pending/errored for this sibling on the same transaction.
          pending_sibling = create_applicant('14', status: 'INELIGIBLE', eligibility_resolved: false)
          add_letter(pending_sibling, mail_status_date: '2026-01-04')
          add_letter(pending_sibling, mail_status_date: '2026-06-16')

          summary = described_class.champva_eligibility_summary(transaction_uuid, user)
          applicants = summary[:applicants]
          alert = summary[:repeat_ineligibility_alert]
          jane_entry = applicants.find { |a| a['firstName'] == 'Jane' }
          pending_entry = applicants.find { |a| a['firstName'].nil? }

          expect(jane_entry['hasRepeatIneligibilityLetter']).to be(true)
          # Only Jane is named (no "and" joiner), confirming the still-unresolved sibling
          # never contributes to the shared name list even once they're eventually excluded.
          expect(alert['title']).to include("Jane's eligibility")
          expect(alert['title']).not_to include('and')
          expect(pending_entry['hasRepeatIneligibilityLetter']).to be(false)
        end
      end

      describe 'latestUpdateDate' do
        def create_applicant(icn, ves_status_updated_date: nil, eligibility_resolved: false)
          IvcChampvaApplicant.create!(
            transaction_uuid:,
            applicant_icn: icn,
            person_type: 'BENEFICIARY',
            eligibility_resolved:,
            ves_status_updated_date:
          )
        end

        def add_letter(applicant, mail_status_date:, mail_status: 'MAILED_BY_PRINT_VENDOR')
          applicant.ivc_champva_letters.create!(
            form_number: 'CCL-A43a.ENC', mail_status:, mail_status_date: Time.zone.parse(mail_status_date)
          )
        end

        def latest_update_date
          described_class.champva_eligibility_summary(transaction_uuid, user)[:latest_update_date]
        end

        it 'returns nil when no applicant has a qualifying eligibility date or letter' do
          create_applicant('1')

          expect(latest_update_date).to be_nil
        end

        it 'considers the most recent qualifying VES eligibility date when only eligibility dates exist' do
          create_applicant('1', ves_status_updated_date: Date.new(2026, 3, 1), eligibility_resolved: true)
          create_applicant('2', ves_status_updated_date: Date.new(2026, 6, 15), eligibility_resolved: true)

          expect(latest_update_date).to eq('2026-06-15')
        end

        it 'considers the most recent qualifying CCL letter date when only letters exist' do
          applicant = create_applicant('1')
          add_letter(applicant, mail_status_date: '2026-04-10T00:00:00Z')
          add_letter(applicant, mail_status_date: '2026-05-20T00:00:00Z')

          expect(latest_update_date).to eq('2026-05-20')
        end

        it 'returns the eligibility date when it is more recent than the qualifying letter date' do
          applicant = create_applicant('1', ves_status_updated_date: Date.new(2026, 8, 1), eligibility_resolved: true)
          add_letter(applicant, mail_status_date: '2026-05-20T00:00:00Z')

          expect(latest_update_date).to eq('2026-08-01')
        end

        it 'returns the letter date when it is more recent than the qualifying eligibility date' do
          applicant = create_applicant('1', ves_status_updated_date: Date.new(2026, 3, 1), eligibility_resolved: true)
          add_letter(applicant, mail_status_date: '2026-07-04T00:00:00Z')

          expect(latest_update_date).to eq('2026-07-04')
        end

        it 'ignores a letter whose mail status is not in the user-facing sent-letter allowlist' do
          applicant = create_applicant('1', ves_status_updated_date: Date.new(2026, 3, 1), eligibility_resolved: true)
          add_letter(applicant, mail_status_date: '2026-07-04T00:00:00Z', mail_status: 'UNKNOWN')

          # The later (2026-07-04) date would win if the non-user-facing letter counted; it must
          # not, so the qualifying eligibility date (2026-03-01) is what's actually returned.
          expect(latest_update_date).to eq('2026-03-01')
        end

        it 'does not treat a withheld stale prior-application eligibility date as current activity, ' \
           'but still considers a qualifying letter for the same applicant' do
          # Mirrors ChampvaEligibilityService's stale_prior_application_status? gate: a determination
          # carried over from a prior application is never persisted (ves_status_updated_date stays
          # nil) until a post-submission letter confirms it applies to the current application --
          # this spec works directly against already-persisted records, so it models that withheld
          # state directly (nil) rather than re-running the gate itself.
          applicant = create_applicant('1') # eligibility_resolved: false, ves_status_updated_date: nil
          add_letter(applicant, mail_status_date: '2026-06-01T00:00:00Z')

          expect(latest_update_date).to eq('2026-06-01')
        end

        it 'considers the most recent qualifying date across multiple applicants, not just the first' do
          create_applicant('1', ves_status_updated_date: Date.new(2026, 1, 1), eligibility_resolved: true)
          later_applicant = create_applicant('2')
          add_letter(later_applicant, mail_status_date: '2026-09-09T00:00:00Z')

          expect(latest_update_date).to eq('2026-09-09')
        end
      end
    end
  end

  describe '.translate_ves_reason' do
    it 'returns nil for blank input' do
      expect(described_class.translate_ves_reason(nil, 'Jane')).to be_nil
      expect(described_class.translate_ves_reason('', 'Jane')).to be_nil
    end

    it 'returns the mapped value with the name substituted for [Name] (case-insensitive lookup)' do
      expected = "Jane's not eligible for CHAMPVA benefits because they got married and are no longer a " \
                 "dependent of the Veteran sponsor.\n\nWe mailed Jane a letter that has more information " \
                 'about our decision. It should arrive within 10 business days.'
      expect(described_class.translate_ves_reason('child married', 'Jane')).to eq(expected)
      expect(described_class.translate_ves_reason('CHILD MARRIED', 'Jane')).to eq(expected)
      expect(described_class.translate_ves_reason('  Child Married  ', 'Jane')).to eq(expected)
    end

    it 'falls back to "The applicant" when no name is given' do
      expect(described_class.translate_ves_reason('child married'))
        .to start_with("The applicant's not eligible for CHAMPVA benefits")
    end

    it 'returns nil for an unmapped reason code' do
      expect(described_class.translate_ves_reason('Some unknown reason', 'Jane')).to be_nil
    end

    it 'returns nil for a reason code with no plain-language text yet (e.g. sponsor-only codes)' do
      expect(described_class.translate_ves_reason('p&t', 'Jane')).to be_nil
    end

    it 'substitutes [Name] everywhere it appears, including mid-string' do
      result = described_class.translate_ves_reason('adopted >2yrs spon dod', 'Jane')
      expect(result).not_to include('John')
      expect(result).to include('We mailed Jane a letter')
    end
  end

  describe '.ves_eligibility_reason_link_for' do
    it 'returns nil for blank input' do
      expect(described_class.ves_eligibility_reason_link_for(nil)).to be_nil
      expect(described_class.ves_eligibility_reason_link_for('')).to be_nil
    end

    it 'returns nil for a reason code with no link' do
      expect(described_class.ves_eligibility_reason_link_for('child married')).to be_nil
    end

    it 'returns the link as a separate { text, url } hash instead of embedding it in the reason text' do
      link = described_class.ves_eligibility_reason_link_for('tricare eligible')
      expect(link).to eq(
        'text' => 'Learn more about TRICARE eligibility on the TRICARE website',
        'url' => 'https://www.tricare.mil/Plans/Eligibility'
      )
      expect(described_class.translate_ves_reason('tricare eligible', 'Jane')).not_to include('Learn more')
    end
  end

  describe '.sponsor_details_for' do
    let(:transaction_uuid) { SecureRandom.uuid }

    it 'returns nil when transaction_uuid is blank' do
      expect(described_class.sponsor_details_for(nil)).to be_nil
      expect(described_class.sponsor_details_for('')).to be_nil
    end

    it 'returns nil when no sponsor exists for the uuid' do
      expect(described_class.sponsor_details_for(transaction_uuid)).to be_nil
    end

    it 'returns a sponsor hash with the expected keys' do
      IvcChampvaSponsor.create!(
        transaction_uuid:,
        first_name: 'John',
        last_name: 'Smith',
        eligibility_status: 'ELIGIBLE',
        reason: 'Sponsor Ineligible'
      )

      result = described_class.sponsor_details_for(transaction_uuid)
      expect(result).to eq(
        'firstName' => 'John',
        'lastName' => 'Smith',
        'eligibilityStatus' => 'ELIGIBLE',
        'eligibilityReason' => "John's not eligible for CHAMPVA benefits because the Veteran sponsor doesn’t " \
                               'have a permanent and total disability. The Veteran sponsor must have a ' \
                               'disability that we’ve rated as 100% disabling and that’s not expected to ' \
                               "improve.\n\nWe mailed John a letter that has more information about our " \
                               'decision. It should arrive within 10 business days.',
        'eligibilityReasonLink' => nil
      )
    end

    it 'translates known VES reason codes and substitutes the sponsor name' do
      IvcChampvaSponsor.create!(
        transaction_uuid:,
        first_name: 'John',
        reason: 'sponsor ineligible'
      )

      result = described_class.sponsor_details_for(transaction_uuid)
      expect(result['eligibilityReason']).to start_with("John's not eligible for CHAMPVA benefits")
    end
  end
end
