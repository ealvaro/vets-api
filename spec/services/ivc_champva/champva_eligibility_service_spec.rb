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
      allow(StatsD).to receive(:increment)
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

    it 'recovers via decrypt-and-match when create! races with another process on the same ' \
       'applicant (RecordNotUnique), instead of raising PG::UndefinedColumn' do
      sponsor_icn = '0000001200603250V008079000000'
      concurrent_sponsor = nil

      # Simulates another concurrent run's create! landing first for this exact
      # (transaction_uuid, applicant_icn) pair, in the window between this run's own
      # existing-records check and its own create! call -- the real unique index on
      # (transaction_uuid, applicant_icn_ciphertext) then raises RecordNotUnique for this
      # run's create!, exactly as it would in production. The row has to actually exist
      # for the rescue's decrypt-and-match fallback to find it, since applicant_icn isn't
      # a queryable column (see the model's has_encrypted declaration) --
      # find_by/where(applicant_icn:) raises PG::UndefinedColumn, which is the bug this
      # regression-tests. Pre-creating the row before .call runs isn't equivalent: it
      # would satisfy existing_applicant_records' cache check and short-circuit the whole
      # sync before create_applicant_record's rescue is ever reached.
      allow(IvcChampvaApplicant).to receive(:create!).and_wrap_original do |original, **kwargs|
        if kwargs[:applicant_icn] == sponsor_icn
          concurrent_sponsor = original.call(**kwargs)
          raise ActiveRecord::RecordNotUnique, 'duplicate key'
        else
          original.call(**kwargs)
        end
      end

      result = described_class.new(transaction_uuid).call

      expect(result[:status]).to eq('success')
      expect(result[:created_count]).to eq(1) # beneficiary only -- sponsor already existed
      expect(result[:existing_count]).to eq(1) # sponsor recovered via the rescue branch
      expect(IvcChampvaApplicant.where(transaction_uuid:).count).to eq(2)

      sponsor_applicant = IvcChampvaApplicant.where(transaction_uuid:)
                                             .find { |record| record.applicant_icn == sponsor_icn }
      expect(sponsor_applicant.id).to eq(concurrent_sponsor.id)
    end

    it 're-raises RecordNotUnique when the decrypt-and-match fallback finds no matching row' do
      sponsor_icn = '0000001200603250V008079000000'

      # Simulates RecordNotUnique firing for a reason OTHER than the normal concurrent-
      # create race this rescue assumes (e.g. the other process's row was deleted before
      # this rescue could re-fetch it) -- the decrypt-and-match lookup then finds nothing,
      # and that must fail loudly and locally rather than writing nil into
      # existing_by_icn, where persist_person_records' own .uniq(&:id) would raise a
      # confusing NoMethodError on nil.id far from the real cause.
      allow(IvcChampvaApplicant).to receive(:create!).and_wrap_original do |original, **kwargs|
        if kwargs[:applicant_icn] == sponsor_icn
          raise ActiveRecord::RecordNotUnique, 'duplicate key'
        else
          original.call(**kwargs)
        end
      end

      expect { described_class.new(transaction_uuid).call }.to raise_error(ActiveRecord::RecordNotUnique)
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

        it 'does not persist a duplicate letter when VES returns the same form_number with ' \
           'different casing' do
          described_class.new(transaction_uuid).call

          recased_correspondence = mail_correspondence.deep_dup
          recased_correspondence['letterTemplate']['formNumber'] = 'ccl-a43a.enc'
          recased_response = {
            'vfmpProgramsInfo' => { 'relationships' => [] }, 'mailCorrespondences' => [recased_correspondence]
          }
          allow(ves_client).to receive(:get_ee_summary).and_return(recased_response)

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

      context 'when the letter is not on the CHAMPVA approved-letter allowlist' do
        let(:mail_status_date) { 1.day.from_now.iso8601 }

        context 'and the form number shares a prefix with an approved letter but is not itself approved' do
          let(:mail_correspondence) do
            {
              'letterTemplate' => { 'name' => 'Some Other CG Correspondence', 'formNumber' => 'CG-A99z' },
              'mailStatus' => 'SENT_TO_PRINT_VENDOR',
              'mailStatusDate' => mail_status_date
            }
          end

          it 'does not persist a letter' do
            result = described_class.new(transaction_uuid).call

            expect(result[:letters_created_count]).to eq(0)
            expect(IvcChampvaLetter.count).to eq(0)
          end
        end

        context 'and the form number is entirely unknown/unrelated to CHAMPVA' do
          let(:mail_correspondence) do
            {
              'letterTemplate' => { 'name' => 'ACA Bene Tax Form', 'formNumber' => '742-801' },
              'mailStatus' => 'SENT_TO_PRINT_VENDOR',
              'mailStatusDate' => mail_status_date
            }
          end

          it 'does not persist a letter' do
            result = described_class.new(transaction_uuid).call

            expect(result[:letters_created_count]).to eq(0)
            expect(IvcChampvaLetter.count).to eq(0)
          end
        end
      end

      context 'when VES returns a mix of approved and unapproved correspondence' do
        let(:mail_status_date) { 1.day.from_now.iso8601 }
        let(:ee_summary_response) do
          {
            'vfmpProgramsInfo' => { 'relationships' => [] },
            'mailCorrespondences' => [
              mail_correspondence,
              {
                'letterTemplate' => { 'name' => 'Unrelated Correspondence', 'formNumber' => 'NEW-001' },
                'mailStatus' => 'SENT_TO_PRINT_VENDOR',
                'mailStatusDate' => mail_status_date
              }
            ]
          }
        end

        it 'persists only the approved letter, for every applicant' do
          result = described_class.new(transaction_uuid).call

          expect(result[:letters_created_count]).to eq(2) # one per applicant (sponsor + beneficiary)
          expect(IvcChampvaLetter.count).to eq(2)
          expect(IvcChampvaLetter.pluck(:form_number)).to all(eq('CCL-A43a.ENC'))
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

      context 'when statusUpdatedDate predates submission and a post-submission letter exists ' \
              'but has not actually been sent yet (a pending mail status)' do
        let(:ee_summary_response) do
          super().merge(
            'mailCorrespondences' => [
              {
                'letterTemplate' => { 'name' => 'CHAMPVA Ineligibility Letter', 'formNumber' => 'CCL-A43a.ENC' },
                'mailStatus' => 'PENDING',
                'mailStatusDate' => 1.day.from_now.iso8601
              }
            ]
          )
        end

        it 'does not treat the pending letter as proof, leaving eligibility unresolved' do
          result = described_class.new(transaction_uuid).call

          expect(result[:eligibility_updated_count]).to eq(0)
          applicants = IvcChampvaApplicant.where(transaction_uuid:)
          expect(applicants).to all(have_attributes(eligibility_resolved: false, ves_eligibility_status: nil))
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

    describe 'DataDog instrumentation' do
      it 'increments the call-outcome metric tagged status:success' do
        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.call', tags: ['status:success'])
      end

      it 'increments the call-outcome metric tagged status:pending when the ICN lookup is pending' do
        allow(ves_client).to receive(:get_icns_for_transaction)
          .with(transaction_uuid)
          .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'still processing')

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.call', tags: ['status:pending'])
      end

      it 'increments the call-outcome metric tagged status:error when the ICN lookup errors' do
        allow(ves_client).to receive(:get_icns_for_transaction)
          .with(transaction_uuid)
          .and_raise(IvcChampva::VesApi::VesApiError, 'boom')

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.call', tags: ['status:error'])
      end

      it 'increments the ves-api-error metric tagged operation:icn_lookup, status:pending on a pending ICN lookup' do
        allow(ves_client).to receive(:get_icns_for_transaction)
          .with(transaction_uuid)
          .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'still processing')

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.ves_api_error', tags: ['operation:icn_lookup', 'status:pending'])
      end

      it 'increments the ves-api-error metric tagged operation:icn_lookup, status:error on an ICN lookup error' do
        allow(ves_client).to receive(:get_icns_for_transaction)
          .with(transaction_uuid)
          .and_raise(IvcChampva::VesApi::VesApiError, 'boom')

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.ves_api_error', tags: ['operation:icn_lookup', 'status:error'])
      end

      it 'increments the ves-api-error metric for a per-applicant EE Summary failure, even though ' \
         '#call as a whole still succeeds' do
        allow(ves_client).to receive(:get_ee_summary)
          .with(icn: '0000001200603250V008079000000')
          .and_raise(IvcChampva::VesApi::VesApiError, 'ee summary boom')
        allow(ves_client).to receive(:get_ee_summary)
          .with(icn: '0000001200603251V181504000000')
          .and_return(ee_summary_response)

        result = described_class.new(transaction_uuid).call

        expect(result[:status]).to eq('success')
        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.ves_api_error', tags: ['operation:ee_summary', 'status:error'])
        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.call', tags: ['status:success'])
      end

      it 'increments the ves-api-error metric for a pending per-applicant EE Summary lookup' do
        allow(ves_client).to receive(:get_ee_summary)
          .with(icn: '0000001200603250V008079000000')
          .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'processing')
        allow(ves_client).to receive(:get_ee_summary)
          .with(icn: '0000001200603251V181504000000')
          .and_return(ee_summary_response)

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.ves_api_error', tags: ['operation:ee_summary', 'status:pending'])
      end

      it 'does not increment the stuck-application metric when all applicants are resolved, ' \
         'even if submitted long ago' do
        IvcChampvaForm.where(transaction_uuid:).update_all(created_at: 35.days.ago) # rubocop:disable Rails/SkipsModelValidations

        described_class.new(transaction_uuid).call

        expect(StatsD).not_to have_received(:increment).with('ivc_champva.eligibility.stuck_application')
      end

      context 'when the application has an unresolved applicant' do
        let(:ee_summary_response) { { 'vfmpProgramsInfo' => { 'relationships' => [] } } }

        it 'increments the stuck-application metric once submitted longer ago than the threshold' do
          IvcChampvaForm.where(transaction_uuid:).update_all(created_at: 35.days.ago) # rubocop:disable Rails/SkipsModelValidations

          described_class.new(transaction_uuid).call

          expect(StatsD).to have_received(:increment).with('ivc_champva.eligibility.stuck_application')
        end

        it 'does not increment the stuck-application metric while still within the threshold' do
          described_class.new(transaction_uuid).call

          expect(StatsD).not_to have_received(:increment).with('ivc_champva.eligibility.stuck_application')
        end
      end

      it 'increments the applicant-resolved metric tagged eligible:true when an applicant is resolved eligible' do
        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.applicant_resolved', tags: ['eligible:true']).twice
      end

      it 'increments the applicant-resolved metric tagged eligible:false when an applicant is resolved ineligible' do
        ineligible_summary = ee_summary_response.deep_dup
        ineligible_summary['vfmpProgramsInfo']['relationships'].first['champvaEligibilities'].first['status'] =
          'Ineligible'
        allow(ves_client).to receive(:get_ee_summary).and_return(ineligible_summary)

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment)
          .with('ivc_champva.eligibility.applicant_resolved', tags: ['eligible:false']).twice
      end

      it 'increments the documents-requested metric when an applicant is flagged as needing documents' do
        ineligible_summary = ee_summary_response.deep_dup
        eligibility = ineligible_summary['vfmpProgramsInfo']['relationships'].first['champvaEligibilities'].first
        eligibility['status'] = 'Ineligible'
        eligibility['reason'] = IvcChampva::ChampvaEligibilityService::DOCUMENTS_REQUESTED_REASONS.first
        allow(ves_client).to receive(:get_ee_summary).and_return(ineligible_summary)

        described_class.new(transaction_uuid).call

        expect(StatsD).to have_received(:increment).with('ivc_champva.eligibility.documents_requested').twice
      end

      it 'does not increment the documents-requested metric when documents are not needed' do
        described_class.new(transaction_uuid).call

        expect(StatsD).not_to have_received(:increment).with('ivc_champva.eligibility.documents_requested')
      end
    end
  end

  describe '.benefits_card_for' do
    let(:ves_client) { instance_double(IvcChampva::VesApi::Client) }
    let(:user) { instance_double(User, icn: '0000001200603250V008079000000', first_name: 'Alex', last_name: 'Doe') }
    let(:as_of) { Date.new(2026, 6, 15) }

    def ee_summary_with_dates(periods)
      {
        'vfmpProgramsInfo' => {
          'relationships' => [
            { 'champvaEligibilities' => [{ 'eligibilityDates' => periods }] }
          ]
        }
      }
    end

    it 'queries the ChampvaDigitalCardData dataset with the user ICN' do
      expect(ves_client).to receive(:get_ee_summary)
        .with(icn: user.icn, dataset: 'ChampvaDigitalCardData')
        .and_return(ee_summary_with_dates([{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }]))

      described_class.benefits_card_for(user, ves_client:, as_of:)
    end

    it 'returns formatted card attributes for a covering period' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates([{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }])
      )

      result = described_class.benefits_card_for(user, ves_client:, as_of:)

      expect(result).to eq(
        status: :ok,
        attributes: {
          full_name: 'Alex Doe',
          effective_date: '01/2026',
          expiration_date: '01/2028'
        }
      )
    end

    it 'returns ok with a nil expiration_date when endDate is omitted' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates([{ 'startDate' => '2020-01-01' }])
      )

      result = described_class.benefits_card_for(user, ves_client:, as_of:)

      expect(result[:status]).to eq(:ok)
      expect(result[:attributes][:expiration_date]).to be_nil
      expect(result[:attributes][:effective_date]).to eq('01/2020')
    end

    it 'returns not_enrolled when relationships are empty' do
      allow(ves_client).to receive(:get_ee_summary).and_return({ 'vfmpProgramsInfo' => { 'relationships' => [] } })

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns not_enrolled when the period is expired' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates([{ 'startDate' => '2020-01-01', 'endDate' => '2021-01-31' }])
      )

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns not_enrolled when the period starts in the future' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates([{ 'startDate' => '2027-01-01', 'endDate' => '2028-01-31' }])
      )

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'picks the covering period with the latest startDate' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates(
          [
            { 'startDate' => '2011-01-01', 'endDate' => '2028-01-31' },
            { 'startDate' => '2024-06-01', 'endDate' => '2028-12-31' }
          ]
        )
      )

      result = described_class.benefits_card_for(user, ves_client:, as_of:)

      expect(result[:attributes][:effective_date]).to eq('06/2024')
      expect(result[:attributes][:expiration_date]).to eq('12/2028')
    end

    it 'treats a single eligibilityDates hash as one covering period' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates({ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' })
      )

      result = described_class.benefits_card_for(user, ves_client:, as_of:)

      expect(result[:status]).to eq(:ok)
      expect(result[:attributes][:effective_date]).to eq('01/2026')
      expect(result[:attributes][:expiration_date]).to eq('01/2028')
    end

    it 'returns not_enrolled when eligibilityDates is neither an array nor a hash' do
      allow(ves_client).to receive(:get_ee_summary).and_return(ee_summary_with_dates('2026-01-15'))

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns not_enrolled when startDate cannot be parsed' do
      allow(ves_client).to receive(:get_ee_summary).and_return(
        ee_summary_with_dates([{ 'startDate' => 'not-a-date', 'endDate' => '2028-01-31' }])
      )

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns not_enrolled when VES data is still pending' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'pending')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns upstream_timeout when VES times out' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApiTimeoutError, 'timeout')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :upstream_timeout)
    end

    it 'returns upstream_error when VES fails' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApiError, 'response code: 500')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :upstream_error)
    end
  end
end
