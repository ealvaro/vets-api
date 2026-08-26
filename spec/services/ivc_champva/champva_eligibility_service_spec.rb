# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

RSpec.describe IvcChampva::ChampvaEligibilityService do
  describe '#call' do
    let(:transaction_uuid) { SecureRandom.uuid }
    let(:form_uuid) { SecureRandom.uuid }
    let(:ves_client) { instance_double(IvcChampva::VesApi::Client) }
    let(:mpi_service) { instance_double(IvcChampva::MPIService) }
    let(:ves_response) do
      [
        { 'icn' => '0000001200603250V008079000000', 'personUUID' => '682', 'personType' => 'SPONSOR' },
        { 'icn' => '0000001200603251V181504000000', 'personUUID' => '638', 'personType' => 'BENEFICIARY' }
      ]
    end
    let(:ee_summary_response) do
      {
        'vfmpProgramsInfo' => {
          'relationships' => [
            {
              'champvaEligibilities' => [
                {
                  'status' => 'Eligible-Active',
                  'reason' => 'Child younger than 18 years',
                  'qualifyingEventReason' => 'Child born before P&T',
                  'eligibilityDates' => [
                    { 'startDate' => '2011-01-01', 'endDate' => '2028-01-31' }
                  ],
                  'sponsor' => {
                    'icn' => '0000001200581123V296649000000',
                    'champvaStatus' => 'ELIGIBLE',
                    'champvaReason' => 'Sponsor eligible'
                  }
                }
              ]
            }
          ]
        }
      }
    end
    let(:name_response) { { first_name: 'Alex', last_name: 'Veteran' } }

    before do
      create(:ivc_champva_form, form_uuid:, transaction_uuid:)
      allow(IvcChampva::VesApi::Client).to receive(:new).and_return(ves_client)
      allow(IvcChampva::MPIService).to receive(:new).and_return(mpi_service)
      allow(ves_client).to receive(:get_icns_for_transaction).with(transaction_uuid).and_return(ves_response)
      allow(ves_client).to receive(:get_ee_summary).and_return(ee_summary_response)
      allow(mpi_service).to receive(:lookup_name_by_icn).and_return(name_response)
    end

    it 'creates applicants, backfills names, and resolves eligibility on first run' do
      result = described_class.new(transaction_uuid).call

      expect(result[:status]).to eq('success')
      expect(result[:created_count]).to eq(2)
      expect(result[:existing_count]).to eq(0)
      expect(result[:names_updated_count]).to eq(2)
      expect(result[:eligibility_updated_count]).to eq(2)
      expect(result[:cached]).to be(false)
      expect(IvcChampvaApplicant.where(transaction_uuid:).count).to eq(2)

      applicant = IvcChampvaApplicant.where(transaction_uuid:)
                                     .find { |record| record.applicant_icn == '0000001200603250V008079000000' }
      expect(applicant).to be_present
      expect(applicant.applicant_first_name).to eq('Alex')
      expect(applicant.applicant_last_name).to eq('Veteran')
      expect(applicant.ves_eligibility_status).to eq('Eligible-Active')
      expect(applicant.ves_eligibility_reason).to eq('Child younger than 18 years')
      expect(applicant.sponsor_icn).to eq('0000001200581123V296649000000')
      expect(applicant.eligibility_resolved).to be(true)
    end

    it 'uses cached applicants on a subsequent run and does not re-query ICNs from VES' do
      described_class.new(transaction_uuid).call

      second_result = described_class.new(transaction_uuid).call

      expect(second_result[:status]).to eq('success')
      expect(second_result[:created_count]).to eq(0)
      expect(second_result[:existing_count]).to eq(2)
      expect(second_result[:cached]).to be(true)
      expect(IvcChampvaApplicant.where(transaction_uuid:).count).to eq(2)
      expect(ves_client).to have_received(:get_icns_for_transaction).once
    end

    it 'continues to re-query VES for an applicant that is not yet eligible' do
      ineligible_summary = ee_summary_response.deep_dup
      ineligible_summary['vfmpProgramsInfo']['relationships'].first['champvaEligibilities'].first['status'] =
        'Ineligible'
      allow(ves_client).to receive(:get_ee_summary).and_return(ineligible_summary)

      described_class.new(transaction_uuid).call
      second_result = described_class.new(transaction_uuid).call

      expect(second_result[:eligibility_updated_count]).to eq(2)
      expect(ves_client).to have_received(:get_ee_summary).exactly(4).times
    end

    it 'handles duplicate ICNs with different person types without violating uniqueness' do
      allow(ves_client).to receive(:get_icns_for_transaction).with(transaction_uuid).and_return(
        [
          { 'icn' => '0000001200603250V008079000000', 'personUUID' => '682', 'personType' => 'SPONSOR' },
          { 'icn' => '0000001200603250V008079000000', 'personUUID' => '683', 'personType' => 'BENEFICIARY' }
        ]
      )

      result = described_class.new(transaction_uuid).call

      expect(result[:status]).to eq('success')
      matching = IvcChampvaApplicant.where(transaction_uuid:)
                                    .count { |record| record.applicant_icn == '0000001200603250V008079000000' }
      expect(matching).to eq(1)
    end

    it 'only backfills names for applicants missing first/last name values' do
      create(
        :ivc_champva_applicant,
        transaction_uuid:,
        applicant_icn: '0000001200603250V008079000000',
        person_type: 'SPONSOR',
        applicant_first_name: 'Existing',
        applicant_last_name: 'Name'
      )
      create(
        :ivc_champva_applicant,
        transaction_uuid:,
        applicant_icn: '0000001200603251V181504000000',
        person_type: 'BENEFICIARY',
        applicant_first_name: nil,
        applicant_last_name: nil
      )

      result = described_class.new(transaction_uuid).call

      expect(result[:cached]).to be(true)
      expect(result[:names_updated_count]).to eq(1)
      expect(mpi_service).to have_received(:lookup_name_by_icn)
        .once
        .with('0000001200603251V181504000000')
    end

    it 'continues eligibility resolution when one applicant returns pending' do
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603250V008079000000')
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'processing')
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603251V181504000000')
        .and_return(ee_summary_response)

      result = described_class.new(transaction_uuid).call

      expect(result[:status]).to eq('success')
      expect(result[:eligibility_updated_count]).to eq(1)

      pending_applicant = IvcChampvaApplicant.where(transaction_uuid:)
                                             .find { |record| record.applicant_icn == '0000001200603250V008079000000' }
      resolved_applicant = IvcChampvaApplicant.where(transaction_uuid:)
                                              .find { |record| record.applicant_icn == '0000001200603251V181504000000' }
      expect(pending_applicant).to be_present
      expect(resolved_applicant).to be_present

      expect(pending_applicant.eligibility_resolved).to be(false)
      expect(resolved_applicant.eligibility_resolved).to be(true)
    end

    it 'returns pending when the initial ICN VES call is still processing' do
      allow(ves_client).to receive(:get_icns_for_transaction)
        .with(transaction_uuid)
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'still processing')

      result = described_class.new(transaction_uuid).call

      expect(result).to include(
        status: 'pending',
        persons: [],
        created_count: 0,
        existing_count: 0,
        error: 'still processing'
      )
    end

    it 'persists a sponsor record from the EE summary with the name looked up in MPI' do
      described_class.new(transaction_uuid).call

      sponsors = IvcChampvaSponsor.where(transaction_uuid:)
      expect(sponsors.count).to eq(1)

      sponsor = sponsors.first
      expect(sponsor.sponsor_icn).to eq('0000001200581123V296649000000')
      expect(sponsor.first_name).to eq('Alex')
      expect(sponsor.last_name).to eq('Veteran')
      expect(sponsor.eligibility_status).to eq('ELIGIBLE')
      expect(sponsor.reason).to eq('Sponsor eligible')
    end

    it 'does not create a duplicate sponsor record on a subsequent run' do
      described_class.new(transaction_uuid).call

      expect { described_class.new(transaction_uuid).call }
        .not_to(change { IvcChampvaSponsor.where(transaction_uuid:).count }.from(1))
    end

    it 'leaves an existing sponsor record untouched' do
      existing = IvcChampvaSponsor.create!(
        transaction_uuid:,
        sponsor_icn: 'PRE-EXISTING-ICN',
        first_name: 'Old',
        last_name: 'Sponsor',
        eligibility_status: 'STALE',
        reason: 'old reason'
      )

      described_class.new(transaction_uuid).call

      existing.reload
      expect(IvcChampvaSponsor.where(transaction_uuid:).count).to eq(1)
      expect(existing.sponsor_icn).to eq('PRE-EXISTING-ICN')
      expect(existing.eligibility_status).to eq('STALE')
    end

    describe 'letter persistence' do
      let(:mail_correspondence) do
        {
          'letterTemplate' => { 'name' => 'CHAMPVA Acceptance Letter', 'formNumber' => 'CCL-A43a.ENC' },
          'mailStatus' => 'SENT_TO_PRINT_VENDOR',
          'mailStatusDate' => mail_status_date
        }
      end
      let(:ee_summary_response) do
        { 'vfmpProgramsInfo' => { 'relationships' => [] }, 'mailCorrespondences' => [mail_correspondence] }
      end

      context 'when the letter was mailed after the application was submitted' do
        let(:mail_status_date) { 1.day.from_now.iso8601 }

        it 'persists a new letter for each applicant' do
          result = described_class.new(transaction_uuid).call

          expect(result[:letters_created_count]).to eq(2)
          expect(IvcChampvaLetter.count).to eq(2)

          letter = IvcChampvaLetter.first
          expect(letter.letter_name).to eq('CHAMPVA Acceptance Letter')
          expect(letter.form_number).to eq('CCL-A43a.ENC')
          expect(letter.mail_status).to eq('SENT_TO_PRINT_VENDOR')
          expect(letter.mail_status_date).to be_within(1.second).of(Time.zone.parse(mail_status_date))
        end

        it 'does not persist a duplicate letter on a subsequent call' do
          described_class.new(transaction_uuid).call

          expect { described_class.new(transaction_uuid).call }
            .not_to(change(IvcChampvaLetter, :count).from(2))
        end
      end

      context 'when the letter was mailed before the application was submitted' do
        let(:mail_status_date) { 10.days.ago.iso8601 }

        it 'does not persist a letter' do
          result = described_class.new(transaction_uuid).call

          expect(result[:letters_created_count]).to eq(0)
          expect(IvcChampvaLetter.count).to eq(0)
        end
      end

      context 'when VES omits the letter template form number' do
        let(:mail_status_date) { 1.day.from_now.iso8601 }
        let(:mail_correspondence) do
          {
            'letterTemplate' => { 'name' => 'CHAMPVA Acceptance Letter' },
            'mailStatus' => 'SENT_TO_PRINT_VENDOR',
            'mailStatusDate' => mail_status_date
          }
        end

        it 'does not persist a letter or raise' do
          result = described_class.new(transaction_uuid).call

          expect(result[:letters_created_count]).to eq(0)
          expect(IvcChampvaLetter.count).to eq(0)
        end
      end

      context 'when VES has not returned any letter history yet' do
        let(:ee_summary_response) { { 'vfmpProgramsInfo' => { 'relationships' => [] } } }

        it 'does not persist any letters or raise' do
          result = described_class.new(transaction_uuid).call

          expect(result[:status]).to eq('success')
          expect(result[:letters_created_count]).to eq(0)
          expect(IvcChampvaLetter.count).to eq(0)
        end
      end

      context 'when VES returns multiple status updates for the same letter' do
        let(:mail_status_date) { 2.days.from_now.iso8601 }
        let(:ee_summary_response) do
          {
            'vfmpProgramsInfo' => { 'relationships' => [] },
            'mailCorrespondences' => [
              mail_correspondence.merge(
                'mailStatus' => 'SENT_TO_PRINT_VENDOR', 'mailStatusDate' => 2.days.from_now.iso8601
              ),
              mail_correspondence.merge('mailStatus' => 'DELIVERED', 'mailStatusDate' => 3.days.from_now.iso8601)
            ]
          }
        end

        it 'persists each status update as a separate letter record' do
          described_class.new(transaction_uuid).call

          applicant = IvcChampvaApplicant.where(transaction_uuid:).first
          statuses = applicant.ivc_champva_letters.order(:mail_status_date).pluck(:mail_status)
          expect(statuses).to eq(%w[SENT_TO_PRINT_VENDOR DELIVERED])
        end
      end

      context 'when a new letter arrives after the applicant is already confirmed eligible' do
        let(:eligible_summary) do
          {
            'vfmpProgramsInfo' => {
              'relationships' => [
                { 'champvaEligibilities' => [{ 'status' => 'Eligible-Active', 'reason' => 'Auto-enrolled' }] }
              ]
            }
          }
        end
        let(:mail_status_date) { 1.day.from_now.iso8601 }

        it 'still persists the new letter on a later call' do
          allow(ves_client).to receive(:get_ee_summary).and_return(eligible_summary)
          described_class.new(transaction_uuid).call
          expect(IvcChampvaApplicant.where(transaction_uuid:)).to all(be_eligible)

          allow(ves_client).to receive(:get_ee_summary).and_return(ee_summary_response)
          second_result = described_class.new(transaction_uuid).call

          expect(second_result[:letters_created_count]).to eq(2)
          expect(IvcChampvaLetter.count).to eq(2)
        end
      end
    end

    describe 'stale prior-application eligibility status' do
      let(:stale_status_updated_date) { '2025-02-01' }
      let(:ee_summary_response) do
        {
          'vfmpProgramsInfo' => {
            'relationships' => [
              {
                'champvaEligibilities' => [
                  {
                    'status' => 'Ineligible',
                    'reason' => 'child married',
                    'statusUpdatedDate' => stale_status_updated_date,
                    'sponsor' => {
                      'icn' => '0000001200581123V296649000000', 'champvaStatus' => 'ELIGIBLE', 'champvaReason' => 'P&T'
                    }
                  }
                ]
              }
            ]
          }
        }
      end

      before do
        # Backdates the form created in the outer `before` so '2025-02-01' unambiguously
        # predates the application's submission, regardless of when specs actually run.
        IvcChampvaForm.where(transaction_uuid:).update_all(created_at: Time.zone.parse('2026-01-01')) # rubocop:disable Rails/SkipsModelValidations
      end

      context 'when statusUpdatedDate predates the application submission and no letter exists yet' do
        it 'does not persist eligibility, leaving it unresolved' do
          result = described_class.new(transaction_uuid).call

          expect(result[:eligibility_updated_count]).to eq(0)
          applicants = IvcChampvaApplicant.where(transaction_uuid:)
          expect(applicants).to all(have_attributes(eligibility_resolved: false, ves_eligibility_status: nil))
        end

        it 'does not persist the stale sponsor record either' do
          described_class.new(transaction_uuid).call

          expect(IvcChampvaSponsor.where(transaction_uuid:)).to be_empty
        end
      end

      context 'when statusUpdatedDate predates submission but a post-submission letter now exists' do
        let(:ee_summary_response) do
          super().merge(
            'mailCorrespondences' => [
              {
                'letterTemplate' => { 'name' => 'CHAMPVA Ineligibility Letter', 'formNumber' => 'CCL-A43a.ENC' },
                'mailStatus' => 'MAILED_BY_PRINT_VENDOR',
                'mailStatusDate' => 1.day.from_now.iso8601
              }
            ]
          )
        end

        it 'persists eligibility once a letter confirms it, even though the status itself is unchanged' do
          result = described_class.new(transaction_uuid).call

          expect(result[:eligibility_updated_count]).to eq(2)
          applicants = IvcChampvaApplicant.where(transaction_uuid:)
          expect(applicants).to all(have_attributes(eligibility_resolved: true, ves_eligibility_status: 'Ineligible'))
        end
      end

      context 'when statusUpdatedDate is on/after the application submission' do
        # Fixed, deterministic date after the '2026-01-01' submission time set in the outer
        # `before` block above — matches that block's own "regardless of when specs actually
        # run" intent. `1.day.from_now` would only land after 2026-01-01 if the suite happens
        # to run after that date, making the example's pass/fail depend on wall-clock time
        # rather than the behavior under test.
        let(:stale_status_updated_date) { '2026-01-02T00:00:00Z' }

        it 'persists eligibility immediately, no letter required' do
          result = described_class.new(transaction_uuid).call

          expect(result[:eligibility_updated_count]).to eq(2)
        end
      end

      context 'when VES does not supply statusUpdatedDate at all' do
        let(:ee_summary_response) do
          {
            'vfmpProgramsInfo' => {
              'relationships' => [
                { 'champvaEligibilities' => [{ 'status' => 'Ineligible', 'reason' => 'child married' }] }
              ]
            }
          }
        end

        it 'persists eligibility immediately, preserving existing behavior' do
          result = described_class.new(transaction_uuid).call

          expect(result[:eligibility_updated_count]).to eq(2)
        end
      end
    end

    it 'stops persisting eligibility once an applicant is already eligible, but keeps checking for new letters' do
      described_class.new(transaction_uuid).call
      expect(ves_client).to have_received(:get_ee_summary).twice

      second_result = described_class.new(transaction_uuid).call

      expect(second_result[:eligibility_updated_count]).to eq(0)
      expect(ves_client).to have_received(:get_ee_summary).exactly(4).times
    end

    it 're-queries VES on a subsequent run while an applicant remains ineligible or pending' do
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603250V008079000000')
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'processing')
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603251V181504000000')
        .and_return(ee_summary_response)

      described_class.new(transaction_uuid).call
      second_result = described_class.new(transaction_uuid).call

      # Applicant '251' resolved to Eligible on the first run, so its eligibility is no
      # longer re-persisted on the second. Applicant '250' raises a pending error on every
      # call and never resolves, so it never persists eligibility data either — hence
      # eligibility_updated_count is 0 on the second run.
      expect(second_result[:eligibility_updated_count]).to eq(0)
      expect(ves_client).to have_received(:get_ee_summary).with(icn: '0000001200603250V008079000000').twice
    end
  end
end
