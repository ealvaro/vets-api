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

  describe '.determine_role' do
    it 'is :beneficiary when the payload carries a CHAMPVA eligibility' do
      relationships = [{ 'champvaEligibilities' => [{ 'status' => 'Eligible' }] }]
      data = { 'vfmpProgramsInfo' => { 'relationships' => relationships } }

      expect(described_class.determine_role(data)).to eq(:beneficiary)
    end

    it 'is :beneficiary when only a later relationship carries an eligibility' do
      data = {
        'vfmpProgramsInfo' => {
          'relationships' => [
            { 'champvaEligibilities' => [] },
            { 'champvaEligibilities' => [{ 'status' => 'Eligible' }] }
          ]
        }
      }

      expect(described_class.determine_role(data)).to eq(:beneficiary)
    end

    # A veteran/sponsor and a person with no CHAMPVA record both land here: VES returns empty
    # data for both, so :veteran means only "not a beneficiary".
    it 'is :veteran for the empty payload VES returns for a non-beneficiary' do
      expect(described_class.determine_role({})).to eq(:veteran)
    end

    it 'is :veteran when relationships carry no eligibilities' do
      data = { 'vfmpProgramsInfo' => { 'relationships' => [{ 'relationshipType' => 'Child' }] } }

      expect(described_class.determine_role(data)).to eq(:veteran)
    end

    it 'is :veteran when relationships is not an array' do
      expect(described_class.determine_role({ 'vfmpProgramsInfo' => { 'relationships' => 'none' } })).to eq(:veteran)
    end

    it 'is :veteran when the response is not a hash' do
      expect(described_class.determine_role(nil)).to eq(:veteran)
    end
  end

  describe '.benefits_card_for' do
    let(:ves_client) { instance_double(IvcChampva::VesApi::Client) }
    let(:user) do
      instance_double(
        User,
        icn: '0000001200603250V008079000000',
        first_name: 'Alex',
        last_name: 'Doe',
        birth_date: '1990-01-15'
      )
    end
    let(:as_of) { Date.new(2026, 6, 15) }

    def ee_summary_with_dates(periods, status: 'Eligible')
      {
        'vfmpProgramsInfo' => {
          'relationships' => [
            { 'champvaEligibilities' => [{ 'status' => status, 'eligibilityDates' => periods }] }
          ]
        }
      }
    end

    # Eligible over a window covering as_of, so the enrichment gate is open. `extra` merges in
    # top-level blocks such as demographics or sensitivityInfo.
    def eligible_ee_summary(extra = {})
      ee_summary_with_dates([{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }]).merge(extra)
    end

    def card_for(data)
      allow(ves_client).to receive(:get_ee_summary).and_return(data)
      described_class.benefits_card_for(user, ves_client:, as_of:)
    end

    def info_for(data)
      card_for(data)[:attributes][:beneficiary_infos].first
    end

    def with_addresses(*addresses)
      { 'demographics' => { 'contactInfo' => { 'addresses' => addresses } } }
    end

    def address(type_code, line1, extra = {})
      {
        'addressTypeCode' => type_code,
        'line1' => line1,
        'city' => 'AUSTIN',
        'state' => 'TX',
        'zipCode' => '78701',
        'country' => 'USA'
      }.merge(extra)
    end

    it 'queries the ChampvaDigitalCardData dataset with the user ICN' do
      expect(ves_client).to receive(:get_ee_summary)
        .with(icn: user.icn, dataset: 'ChampvaDigitalCardData')
        .and_return(ee_summary_with_dates([{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }]))

      described_class.benefits_card_for(user, ves_client:, as_of:)
    end

    it 'returns a beneficiary_infos array for an eligible covering period' do
      result = card_for(eligible_ee_summary)

      expect(result).to eq(
        status: :ok,
        attributes: {
          role: 'beneficiary',
          beneficiary_infos: [
            {
              icn: '0000001200603250V008079000000',
              full_name: 'Alex Doe',
              date_of_birth: '1990-01-15',
              mailing_address: nil,
              enrollment_status: 'eligible',
              eligibility_status: 'Eligible',
              eligibility_reason: nil,
              sensitive_record: nil,
              relationship_type: nil,
              effective_date: '2026/01/15',
              expiration_date: '2028/01/31'
            }
          ]
        }
      )
    end

    it 'passes the VES status and reason through untouched for frontend messaging' do
      data = ee_summary_with_dates([{ 'startDate' => '2026-01-15' }])
      data['vfmpProgramsInfo']['relationships'][0]['champvaEligibilities'][0]['reason'] = 'P&T'
      data['vfmpProgramsInfo']['relationships'][0]['relationshipType'] = 'Spouse'

      expect(info_for(data)).to include(
        eligibility_status: 'Eligible',
        eligibility_reason: 'P&T',
        relationship_type: 'Spouse'
      )
    end

    it 'returns ok with a nil expiration_date when endDate is omitted' do
      info = info_for(ee_summary_with_dates([{ 'startDate' => '2020-01-01' }]))

      expect(info[:enrollment_status]).to eq('eligible')
      expect(info[:expiration_date]).to be_nil
      expect(info[:effective_date]).to eq('2020/01/01')
    end

    it 'returns not_enrolled when relationships are empty' do
      expect(card_for({ 'vfmpProgramsInfo' => { 'relationships' => [] } })).to eq(status: :not_enrolled)
    end

    # The sponsor flow needs a roster endpoint VES has not delivered yet, so a non-beneficiary
    # is reported as not enrolled rather than branching into it.
    it 'returns not_enrolled for the empty payload VES returns for a non-beneficiary' do
      expect(card_for({})).to eq(status: :not_enrolled)
    end

    it 'picks the covering period with the latest startDate' do
      info = info_for(
        ee_summary_with_dates(
          [
            { 'startDate' => '2011-01-01', 'endDate' => '2028-01-31' },
            { 'startDate' => '2024-06-01', 'endDate' => '2028-12-31' }
          ]
        )
      )

      expect(info[:effective_date]).to eq('2024/06/01')
      expect(info[:expiration_date]).to eq('2028/12/31')
    end

    it 'treats a single eligibilityDates hash as one covering period' do
      info = info_for(ee_summary_with_dates({ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }))

      expect(info[:enrollment_status]).to eq('eligible')
      expect(info[:effective_date]).to eq('2026/01/15')
      expect(info[:expiration_date]).to eq('2028/01/31')
    end

    describe 'the reported status' do
      it 'is :ok for an eligible beneficiary' do
        expect(card_for(eligible_ee_summary)[:status]).to eq(:ok)
      end

      # Distinct from :not_enrolled so the controller can render the two differently: this is a
      # record that does not qualify, that one is no record at all.
      it 'is :ineligible when VES denies the beneficiary' do
        data = ee_summary_with_dates([{ 'startDate' => '2026-01-15' }], status: 'Ineligible')

        expect(card_for(data)).to include(status: :ineligible, enrollment_status: 'ineligible')
      end

      it 'is :ineligible with the specific verdict when the window has closed' do
        data = ee_summary_with_dates([{ 'startDate' => '2020-01-01', 'endDate' => '2021-01-31' }])

        expect(card_for(data)).to include(status: :ineligible, enrollment_status: 'expired')
      end

      it 'is :ineligible with the specific verdict when the window has not opened' do
        data = ee_summary_with_dates([{ 'startDate' => '2027-01-01', 'endDate' => '2028-01-31' }])

        expect(card_for(data)).to include(status: :ineligible, enrollment_status: 'not_yet_effective')
      end

      # The controller withholds these today, so moving ineligibility off a 404 is a controller
      # change rather than a service one.
      it 'still returns the card attributes alongside an :ineligible status' do
        data = ee_summary_with_dates([{ 'startDate' => '2026-01-15' }], status: 'Ineligible')

        expect(card_for(data)[:attributes][:beneficiary_infos].first).to include(
          enrollment_status: 'ineligible',
          effective_date: '2026/01/15'
        )
      end
    end

    describe 'enrollment_status' do
      it 'is expired when the window has closed, and still reports the closed window' do
        info = info_for(ee_summary_with_dates([{ 'startDate' => '2020-01-01', 'endDate' => '2021-01-31' }]))

        expect(info).to include(
          enrollment_status: 'expired',
          effective_date: '2020/01/01',
          expiration_date: '2021/01/31'
        )
      end

      it 'is not_yet_effective when the window has not opened' do
        info = info_for(ee_summary_with_dates([{ 'startDate' => '2027-01-01', 'endDate' => '2028-01-31' }]))

        expect(info).to include(
          enrollment_status: 'not_yet_effective',
          effective_date: '2027/01/01',
          expiration_date: '2028/01/31'
        )
      end

      # Before this ticket the verdict was the date window alone, so an ineligible person inside
      # a live window was issued a card.
      it 'is ineligible when VES denies a beneficiary whose window covers today' do
        info = info_for(
          ee_summary_with_dates([{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }], status: 'Ineligible')
        )

        expect(info).to include(enrollment_status: 'ineligible', eligibility_status: 'Ineligible')
      end

      it 'is ineligible when VES omits the status' do
        info = info_for(ee_summary_with_dates([{ 'startDate' => '2026-01-15' }], status: nil))

        expect(info[:enrollment_status]).to eq('ineligible')
      end

      it 'accepts an eligible status in any casing' do
        info = info_for(ee_summary_with_dates([{ 'startDate' => '2026-01-15' }], status: 'ELIGIBLE'))

        expect(info[:enrollment_status]).to eq('eligible')
      end

      it 'is ineligible when eligibilityDates is neither an array nor a hash' do
        expect(info_for(ee_summary_with_dates('2026-01-15'))).to include(
          enrollment_status: 'ineligible',
          effective_date: nil,
          expiration_date: nil
        )
      end

      # Unparseable is not the same as expired, so it reports ineligible rather than guessing.
      it 'is ineligible when startDate cannot be parsed' do
        info = info_for(ee_summary_with_dates([{ 'startDate' => 'not-a-date', 'endDate' => '2028-01-31' }]))

        expect(info).to include(enrollment_status: 'ineligible', effective_date: nil)
      end
    end

    describe 'enrichment gating' do
      it 'populates name, date of birth, and address for an eligible beneficiary' do
        info = info_for(eligible_ee_summary(with_addresses(address('Permanent', '1 MAIN ST'))))

        expect(info[:full_name]).to eq('Alex Doe')
        expect(info[:date_of_birth]).to eq('1990-01-15')
        expect(info[:mailing_address]).to include(line1: '1 MAIN ST')
      end

      # The frontend only offers a card to eligible people, so the sponsor flow must not pay an
      # MPI call per ineligible beneficiary. Nothing is saved in the beneficiary flow, where the
      # identity is already resolved for the session, but the shape is what the sponsor flow needs.
      it 'leaves name, date of birth, and address null for an ineligible beneficiary' do
        data = ee_summary_with_dates(
          [{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }], status: 'Ineligible'
        ).merge(with_addresses(address('Permanent', '1 MAIN ST')))

        expect(info_for(data)).to include(full_name: nil, date_of_birth: nil, mailing_address: nil)
      end

      it 'still returns the ICN, dates, and VES status for an ineligible beneficiary' do
        data = ee_summary_with_dates(
          [{ 'startDate' => '2026-01-15', 'endDate' => '2028-01-31' }], status: 'Ineligible'
        )

        expect(info_for(data)).to include(
          icn: '0000001200603250V008079000000',
          eligibility_status: 'Ineligible',
          effective_date: '2026/01/15',
          expiration_date: '2028/01/31'
        )
      end
    end

    describe 'mailing address selection' do
      it 'is nil when the dataset carries no demographics' do
        expect(info_for(eligible_ee_summary)[:mailing_address]).to be_nil
      end

      it 'is nil when demographics carries no addresses' do
        data = eligible_ee_summary('demographics' => { 'contactInfo' => {} })

        expect(info_for(data)[:mailing_address]).to be_nil
      end

      it 'maps every address field VES supplies' do
        entry = address(
          'Permanent', '123 MAIN ST',
          'line2' => 'APT 4', 'line3' => 'BLDG C', 'provinceCode' => 'ON',
          'zipPlus4' => '0001', 'postalCode' => 'K1A0B1'
        )

        expect(info_for(eligible_ee_summary(with_addresses(entry)))[:mailing_address]).to eq(
          line1: '123 MAIN ST',
          line2: 'APT 4',
          line3: 'BLDG C',
          city: 'AUSTIN',
          state: 'TX',
          province_code: 'ON',
          zip_code: '78701',
          zip_plus4: '0001',
          postal_code: 'K1A0B1',
          country: 'USA'
        )
      end

      # VES returns one address per type rather than a history, so type decides, not recency.
      it 'prefers the permanent address even when the residential one changed more recently' do
        data = eligible_ee_summary(
          with_addresses(
            address('Permanent', '1 PERMANENT ST', 'addressChangeDateTime' => '2020-01-01T00:00:00.000-05:00'),
            address('Residential', '2 RESIDENTIAL ST', 'addressChangeDateTime' => '2025-06-18T16:24:03.000-05:00')
          )
        )

        expect(info_for(data)[:mailing_address][:line1]).to eq('1 PERMANENT ST')
      end

      # VES writes single letters on submit and full words on read, and only one read sample
      # exists, so both spellings are matched.
      it 'accepts the single-letter address type codes' do
        data = eligible_ee_summary(with_addresses(address('R', '2 RESIDENTIAL ST'), address('P', '1 PERMANENT ST')))

        expect(info_for(data)[:mailing_address][:line1]).to eq('1 PERMANENT ST')
      end

      it 'falls back to the residential address when there is no permanent one' do
        data = eligible_ee_summary(with_addresses(address('Residential', '2 RESIDENTIAL ST')))

        expect(info_for(data)[:mailing_address][:line1]).to eq('2 RESIDENTIAL ST')
      end

      it 'falls back to the only remaining address when its type is unrecognized' do
        data = eligible_ee_summary(with_addresses(address('Correspondence', '3 OTHER ST')))

        expect(info_for(data)[:mailing_address][:line1]).to eq('3 OTHER ST')
      end

      # This feeds a physical mailing, so a known-undeliverable address is worse than none.
      it 'rejects an address VES has flagged as bad' do
        data = eligible_ee_summary(
          with_addresses(
            address('Permanent', '1 BAD ST', 'badAddressReason' => 'UNDELIVERABLE'),
            address('Residential', '2 GOOD ST')
          )
        )

        expect(info_for(data)[:mailing_address][:line1]).to eq('2 GOOD ST')
      end

      it 'rejects an address whose endDate has passed' do
        data = eligible_ee_summary(
          with_addresses(
            address('Permanent', '1 OLD ST', 'endDate' => '2020-01-01'),
            address('Residential', '2 CURRENT ST')
          )
        )

        expect(info_for(data)[:mailing_address][:line1]).to eq('2 CURRENT ST')
      end

      # endDate has no documented format and is absent from real data, so an unparseable value
      # keeps the address rather than discarding a usable one.
      it 'keeps an address whose endDate cannot be parsed' do
        data = eligible_ee_summary(with_addresses(address('Permanent', '1 MAIN ST', 'endDate' => 'unknown')))

        expect(info_for(data)[:mailing_address][:line1]).to eq('1 MAIN ST')
      end

      it 'breaks a same-type tie on the most recent addressChangeDateTime' do
        data = eligible_ee_summary(
          with_addresses(
            address('Permanent', '1 OLDER ST', 'addressChangeDateTime' => '2020-01-01T00:00:00.000-05:00'),
            address('Permanent', '2 NEWER ST', 'addressChangeDateTime' => '2025-06-18T16:24:03.000-05:00')
          )
        )

        expect(info_for(data)[:mailing_address][:line1]).to eq('2 NEWER ST')
      end

      it 'tolerates an unparseable addressChangeDateTime' do
        data = eligible_ee_summary(with_addresses(address('Permanent', '1 MAIN ST', 'addressChangeDateTime' => 'x')))

        expect(info_for(data)[:mailing_address][:line1]).to eq('1 MAIN ST')
      end

      # Time.zone.parse returns nil for junk like "x" and raises ArgumentError for an
      # out-of-range calendar date. Both must be treated as "no timestamp" so a bad
      # VES value cannot blow up the lookup or win a tiebreak.
      it 'treats an out-of-range addressChangeDateTime as missing rather than failing' do
        data = eligible_ee_summary(
          with_addresses(
            address('Permanent', '1 BAD TIME ST', 'addressChangeDateTime' => '2020-13-45'),
            address('Permanent', '2 GOOD TIME ST', 'addressChangeDateTime' => '2025-06-18T16:24:03.000-05:00')
          )
        )

        expect(info_for(data)[:mailing_address][:line1]).to eq('2 GOOD TIME ST')
      end
    end

    describe 'sensitive_record' do
      it 'is true when VES sets the flag' do
        data = eligible_ee_summary('sensitivityInfo' => { 'sensitivityFlag' => true })

        expect(info_for(data)[:sensitive_record]).to be(true)
      end

      it 'is false when VES clears the flag' do
        data = eligible_ee_summary('sensitivityInfo' => { 'sensitivityFlag' => false })

        expect(info_for(data)[:sensitive_record]).to be(false)
      end

      it 'casts the string VES may send instead of a boolean' do
        data = eligible_ee_summary('sensitivityInfo' => { 'sensitivityFlag' => 'true' })

        expect(info_for(data)[:sensitive_record]).to be(true)
      end

      # Defaulting an unknown flag to "not sensitive" is the unsafe direction, and the sponsor
      # flow filters beneficiaries on this value.
      it 'stays nil rather than false when the dataset omits sensitivityInfo' do
        expect(info_for(eligible_ee_summary)[:sensitive_record]).to be_nil
      end
    end

    it 'returns not_enrolled when VES data is still pending' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'pending')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:)).to eq(status: :not_enrolled)
    end

    it 'returns upstream_timeout when VES times out' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApiTimeoutError, 'timeout')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:))
        .to eq(status: :upstream_timeout, error_class: 'IvcChampva::VesApi::VesApiTimeoutError')
    end

    it 'returns upstream_error when VES fails' do
      allow(ves_client).to receive(:get_ee_summary)
        .and_raise(IvcChampva::VesApi::VesApiError, 'response code: 500')

      expect(described_class.benefits_card_for(user, ves_client:, as_of:))
        .to eq(status: :upstream_error, error_class: 'IvcChampva::VesApi::VesApiError')
    end

    context 'when reporting the failure to Datadog' do
      let(:monitor) { instance_double(IvcChampva::Monitor, track_ves_call_failure: nil) }

      before { allow(IvcChampva::Monitor).to receive(:new).and_return(monitor) }

      it 'tracks the VES call failure, since the rendered error is generic' do
        error = IvcChampva::VesApi::VesApiError.new('response code: 403')
        allow(ves_client).to receive(:get_ee_summary).and_raise(error)

        described_class.benefits_card_for(user, ves_client:, as_of:)

        expect(monitor).to have_received(:track_ves_call_failure).with('ee_summary', :upstream_error, error)
      end

      it 'tracks the VES call failure when VES times out' do
        error = IvcChampva::VesApi::VesApiTimeoutError.new('timeout')
        allow(ves_client).to receive(:get_ee_summary).and_raise(error)

        described_class.benefits_card_for(user, ves_client:, as_of:)

        expect(monitor).to have_received(:track_ves_call_failure).with('ee_summary', :upstream_timeout, error)
      end

      it 'does not track a VES failure for a pending application, which is an expected outcome' do
        allow(ves_client).to receive(:get_ee_summary)
          .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'pending')

        described_class.benefits_card_for(user, ves_client:, as_of:)

        expect(monitor).not_to have_received(:track_ves_call_failure)
      end
    end
  end
end
