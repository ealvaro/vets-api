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
      expect(result[:pega_status]).to eq('processed - eligibility determination unknown')
      expect(IvcChampvaForm.find_by(form_uuid:)&.pega_status).to eq('processed - eligibility determination unknown')
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

    it 'updates only the targeted form UUIDs when form_uuids are provided' do
      untouched_form = create(:ivc_champva_form, transaction_uuid:)

      described_class.new(transaction_uuid, form_uuids: [form_uuid]).call

      expect(IvcChampvaForm.find_by(form_uuid:)&.pega_status).to eq('processed - eligibility determination unknown')
      expect(untouched_form.reload.pega_status).not_to eq('processed - eligibility determination unknown')
    end

    it 'updates only one row per form_uuid when multiple rows share the same form_uuid' do
      older = create(
        :ivc_champva_form,
        form_uuid:,
        transaction_uuid:,
        updated_at: 2.days.ago,
        pega_status: nil
      )
      newer = create(
        :ivc_champva_form,
        form_uuid:,
        transaction_uuid:,
        updated_at: 1.day.ago,
        pega_status: nil
      )

      result = described_class.new(transaction_uuid, form_uuids: [form_uuid]).call

      expect(result[:pega_status]).to eq('processed - eligibility determination unknown')
      updated_rows = IvcChampvaForm.where(form_uuid:, pega_status: 'processed - eligibility determination unknown')
      expect(updated_rows.count).to eq(1)
      statuses = [older.reload.pega_status, newer.reload.pega_status]
      expect(statuses.count('processed - eligibility determination unknown')).to be <= 1
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

    it 'skips VES eligibility calls once every applicant is already resolved' do
      described_class.new(transaction_uuid).call
      expect(ves_client).to have_received(:get_ee_summary).twice

      second_result = described_class.new(transaction_uuid).call

      expect(second_result[:eligibility_updated_count]).to eq(0)
      expect(ves_client).to have_received(:get_ee_summary).twice
    end

    it 're-queries VES on a subsequent run while an applicant remains unresolved' do
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603250V008079000000')
        .and_raise(IvcChampva::VesApi::VesApplicationPendingError, 'processing')
      allow(ves_client).to receive(:get_ee_summary)
        .with(icn: '0000001200603251V181504000000')
        .and_return(ee_summary_response)

      described_class.new(transaction_uuid).call
      second_result = described_class.new(transaction_uuid).call

      expect(second_result[:eligibility_updated_count]).to eq(1)
      expect(ves_client).to have_received(:get_ee_summary).with(icn: '0000001200603250V008079000000').twice
    end
  end
end
