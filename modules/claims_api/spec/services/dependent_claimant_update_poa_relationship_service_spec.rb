# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::DependentClaimantUpdatePoaRelationshipService do
  subject(:service) do
    described_class.new(
      poa_id: 'poa-123',
      poa_code:,
      dependent_participant_id:,
      veteran_file_number:,
      allow_poa_access:,
      allow_poa_cadd: allow_poa_c_add,
      claimant_ssn:
    )
  end

  let(:poa_code) { '074' }
  let(:dependent_participant_id) { '600052700' }
  let(:veteran_file_number) { '796163671' }
  let(:claimant_ssn) { '796163672' }
  let(:allow_poa_access) { 'Y' }
  let(:allow_poa_c_add) { 'N' }

  let(:use_update_poa_relationship) { true }
  let(:use_local_bgs_for_vbms_updater) { true }

  before do
    allow(ClaimsApi::Logger).to receive(:log)
    allow(Flipper).to receive(:enabled?).with(:claims_api_use_update_poa_relationship)
                                        .and_return(use_update_poa_relationship)
    allow(Flipper).to receive(:enabled?).with(:claims_api_poa_vbms_updater_uses_local_bgs)
                                        .and_return(use_local_bgs_for_vbms_updater)
  end

  describe '#assign_poa_to_dependent!' do
    context 'when both toggles use local_bgs-backed services' do
      let(:use_update_poa_relationship) { true }
      let(:use_local_bgs_for_vbms_updater) { true }

      it 'updates relationship and access successfully' do
        manage_rep_service = instance_double(ClaimsApi::ManageRepresentativeService)
        corporate_update_service = instance_double(ClaimsApi::CorporateUpdateWebService)

        expect(ClaimsApi::ManageRepresentativeService).to receive(:new).with(
          external_uid: dependent_participant_id,
          external_key: dependent_participant_id
        ).and_return(manage_rep_service)

        expect(ClaimsApi::CorporateUpdateWebService).to receive(:new).with(
          external_uid: dependent_participant_id,
          external_key: dependent_participant_id
        ).and_return(corporate_update_service)

        expect(manage_rep_service).to receive(:update_poa_relationship).with(
          pctpnt_id: dependent_participant_id,
          file_number: veteran_file_number,
          ssn: claimant_ssn,
          poa_code:
        ).and_return({ 'dateRequestAccepted' => Time.current.iso8601 })

        expect(corporate_update_service).to receive(:update_poa_access).with(
          participant_id: dependent_participant_id,
          poa_code:,
          allow_poa_access:,
          allow_poa_c_add:
        ).and_return({ return_code: 'GUIE50000' })

        expect(service.assign_poa_to_dependent!).to eq(:success)
      end
    end

    context 'when both toggles use bgs-ext services' do
      let(:use_update_poa_relationship) { false }
      let(:use_local_bgs_for_vbms_updater) { false }

      it 'updates relationship and access successfully' do
        bgs_service = instance_double(BGS::Services)
        vet_record = instance_double(BGS::VetRecordWebService)
        corporate_update = instance_double(BGS::CorporateUpdateWebService)

        allow(BGS::Services).to receive(:new).with(
          external_uid: dependent_participant_id,
          external_key: dependent_participant_id
        ).and_return(bgs_service)

        expect(bgs_service).to receive(:vet_record).and_return(vet_record)
        expect(vet_record).to receive(:update_birls_record).with(
          file_number: veteran_file_number,
          ssn: claimant_ssn,
          poa_code:
        ).and_return({ return_code: 'BMOD0001' })

        expect(bgs_service).to receive(:corporate_update).and_return(corporate_update)
        expect(corporate_update).to receive(:update_poa_access).with(
          participant_id: dependent_participant_id,
          poa_code:,
          allow_poa_access:,
          allow_poa_c_add:
        ).and_return({ return_code: 'GUIE50000' })

        expect(service.assign_poa_to_dependent!).to eq(:success)
      end
    end

    context 'when relationship update fails' do
      let(:use_update_poa_relationship) { true }

      it 'raises service error with active service name and logs it' do
        manage_rep_service = instance_double(ClaimsApi::ManageRepresentativeService)

        allow(ClaimsApi::ManageRepresentativeService).to receive(:new).and_return(manage_rep_service)
        allow(manage_rep_service).to receive(:update_poa_relationship).and_return({})

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to include(
            "Failed to assign POA #{service.instance_variable_get(:@poa_id)} to dependent claimant"
          )
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_update_poa_relationship_service',
          hash_including(
            level: :error,
            poa_id: 'poa-123',
            poa_code:,
            message: a_string_starting_with('Failed to update POA relationship for the dependent in')
          )
        )
      end
    end

    context 'when access update fails' do
      let(:use_update_poa_relationship) { true }
      let(:use_local_bgs_for_vbms_updater) { true }

      it 'raises service error with active service name and logs it' do
        manage_rep_service = instance_double(ClaimsApi::ManageRepresentativeService)
        corporate_update_service = instance_double(ClaimsApi::CorporateUpdateWebService)

        allow(ClaimsApi::ManageRepresentativeService).to receive(:new).and_return(manage_rep_service)
        allow(ClaimsApi::CorporateUpdateWebService).to receive(:new).and_return(corporate_update_service)

        allow(manage_rep_service).to receive(:update_poa_relationship).and_return(
          { 'dateRequestAccepted' => Time.current.iso8601 }
        )
        allow(corporate_update_service).to receive(:update_poa_access).and_return({ return_code: 'GUIE50001' })

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to include(
            "Failed to assign POA #{service.instance_variable_get(:@poa_id)} to dependent claimant"
          )
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_update_poa_relationship_service',
          hash_including(
            level: :error,
            poa_id: 'poa-123',
            poa_code:,
            message: a_string_starting_with('Failed to update POA access for the dependent in')
          )
        )
      end
    end

    context 'when downstream service raises exception with custom detail' do
      let(:use_update_poa_relationship) { true }

      it 'logs detailed message and re-raises original error' do
        manage_rep_service = instance_double(ClaimsApi::ManageRepresentativeService)
        service_error = Common::Exceptions::ServiceError.new(detail: 'Header element CLIENT_MACHINE is missing.')

        allow(ClaimsApi::ManageRepresentativeService).to receive(:new).and_return(manage_rep_service)
        allow(manage_rep_service).to receive(:update_poa_relationship).and_raise(service_error)

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to include(
            "Failed to assign POA #{service.instance_variable_get(:@poa_id)} to dependent claimant"
          )
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_update_poa_relationship_service',
          hash_including(
            level: :error,
            poa_id: 'poa-123',
            poa_code:,
            message: a_string_starting_with(
              "Failed to assign POA #{service.instance_variable_get(:@poa_id)} to dependent claimant"
            )
          )
        )
      end
    end
  end
end
