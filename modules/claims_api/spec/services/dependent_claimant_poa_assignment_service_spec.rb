# frozen_string_literal: true

require 'rails_helper'
require 'bgs_service/local_bgs'

RSpec.describe ClaimsApi::DependentClaimantPoaAssignmentService do
  let(:fallback_service_flag_enabled) { false }
  let(:dependent_participant_id) { '600052700' }
  let(:poa_error_message) { 'Failed to assign POA to dependent' }
  let(:poa_code) { '002' }

  describe '#assign_poa_to_dependent!' do
    let(:service) do
      described_class.new(poa_code:, veteran_participant_id: '600052699', dependent_participant_id:,
                          veteran_file_number: '796163671', claimant_ssn: '796163672')
    end
    let(:mock_find_benefit_claims_status_by_ptcpnt_id) do
      {
        benefit_claims_dto:
        { benefit_claim:
        [{
          appeal_possible: 'No',
          attention_needed: 'Yes',
          base_end_prdct_type_cd: '690',
          benefit_claim_id: '256009',
          bnft_claim_type_cd: '690AUTRWPMC',
          claim_dt: '2013-03-01',
          claim_status: 'RDC',
          claim_status_type: 'Authorization Review',
          decision_notification_sent: 'No',
          development_letter_sent: 'Yes',
          ealiest_evidence_due_date: '2024-08-25',
          end_prdct_type_cd: '691',
          filed5103_waiver_ind: 'Y',
          latest_evidence_recd_date: '2015-09-18',
          max_est_claim_complete_dt: '2013-03-30',
          min_est_claim_complete_dt: '2013-03-28',
          phase_chngd_dt: '2013-03-26T06:24:43',
          phase_type: 'Pending Decision Approval',
          program_type: 'CPD',
          ptcpnt_clmant_id: '600052700',
          ptcpnt_vet_id: '600052699'
        }] }
      }
    end
    let(:mock_find_benefit_claims_status_by_clmant_id) do
      { 'xmlns:ns0': 'http://benefitclaim.services.vetsnet.vba.va.gov/',
        bnft_claim_dto: [{ bnft_claim_id: '256009',
                           bnft_claim_type_cd: '130SSRDE',
                           bnft_claim_type_label: 'Dependency',
                           bnft_claim_type_nm: 'Self Service - Removal of Dependent Exception',
                           bnft_claim_user_display: 'YES',
                           claim_jrsdtn_lctn_id: '331',
                           claim_rcvd_dt: '2024-12-05T00:00:00-06:00',
                           cp_claim_end_prdct_type_cd: '130',
                           jrn_dt: '2025-03-07T05:37:32-06:00',
                           jrn_lctn_id: '283',
                           jrn_obj_id: 'VBMS',
                           jrn_status_type_cd: 'U',
                           jrn_user_id: 'NWQSYSACCT',
                           payee_type_cd: '00',
                           payee_type_nm: 'Veteran',
                           pgm_type_cd: 'CPL',
                           pgm_type_nm: 'Compensation-Pension Live',
                           ptcpnt_clmant_id: '600036156',
                           ptcpnt_clmant_nm: 'BROOKS JERRY',
                           ptcpnt_dposit_acnt_id: '80053',
                           ptcpnt_mail_addrs_id: '16671259',
                           ptcpnt_vet_id: '600036156',
                           scrty_level_type_cd: '5',
                           station_of_jurisdiction: '377',
                           status_type_cd: 'PEND',
                           status_type_nm: 'Pending',
                           svc_type_cd: 'CP',
                           temp_jrsdtn_lctn_id: '359',
                           temporary_station_of_jurisdiction: '330',
                           termnl_digit_nbr: '37' },
                         { bnft_claim_id: '600548102',
                           bnft_claim_type_cd: '400PREDSCHRG',
                           bnft_claim_type_label: 'Compensation',
                           bnft_claim_type_nm: 'eBenefits 526EZ-Pre Discharge (400)',
                           bnft_claim_user_display: 'YES',
                           claim_jrsdtn_lctn_id: '123725',
                           claim_rcvd_dt: '2024-10-31T00:00:00-05:00',
                           claim_suspns_dt: '2024-08-29T15:00:38-05:00',
                           cp_claim_end_prdct_type_cd: '404',
                           intake_jrsdtn_lctn_id: '123686',
                           jrn_dt: '2024-08-29T15:00:38-05:00',
                           jrn_lctn_id: '281',
                           jrn_obj_id: 'cd_clm_pkg.do_update',
                           jrn_status_type_cd: 'U',
                           jrn_user_id: 'vaebenefits',
                           payee_type_cd: '00',
                           payee_type_nm: 'Veteran',
                           pgm_type_cd: 'CPL',
                           pgm_type_nm: 'Compensation-Pension Live',
                           ptcpnt_clmant_id: '600036156',
                           ptcpnt_clmant_nm: 'BROOKS JERRY',
                           ptcpnt_dposit_acnt_id: '80053',
                           ptcpnt_mail_addrs_id: '16564285',
                           ptcpnt_vet_id: '600036156',
                           ptcpnt_vsr_id: '600093804',
                           scrty_level_type_cd: '5',
                           station_of_jurisdiction: '499',
                           status_type_cd: 'CAN',
                           status_type_nm: 'Cancelled',
                           submtr_applcn_type_cd: 'VBMS',
                           submtr_role_type_cd: 'VBA',
                           svc_type_cd: 'CP',
                           temp_jrsdtn_lctn_id: '337',
                           temporary_station_of_jurisdiction: '306',
                           termnl_digit_nbr: '37' }] }
    end
    let(:mock_find_bnft_claim) do
      {
        bnft_claim_dto:
          {
            bnft_claim_id: '256009',
            bnft_claim_type_cd: '690AUTRWPMC',
            bnft_claim_type_label: 'Authorization Review',
            bnft_claim_type_nm: 'PMC-Reviews - Authorization Only',
            bnft_claim_user_display: 'YES',
            claim_jrsdtn_lctn_id: '347',
            claim_rcvd_dt: '2013-03-01T00:00:00-06:00',
            claim_suspns_dt: '2024-08-20T12:09:48-05:00',
            cp_claim_end_prdct_type_cd: '691',
            filed5103_waiver_ind: 'Y',
            jrn_dt: '2024-10-01T11:58:31-05:00',
            jrn_lctn_id: '281',
            jrn_obj_id: 'VAgovAPI',
            jrn_status_type_cd: 'U',
            jrn_user_id: 'VAgovAPI',
            payee_type_cd: '10',
            payee_type_nm: 'Spouse',
            pgm_type_cd: 'CPD',
            pgm_type_nm: 'Compensation-Pension Death',
            ptcpnt_clmant_id: '600052700',
            ptcpnt_clmant_nm: 'CURTIS MARGIE',
            ptcpnt_mail_addrs_id: '16542930',
            ptcpnt_pymt_addrs_id: '14781119',
            ptcpnt_vet_id: '600052699',
            station_of_jurisdiction: '317',
            status_type_cd: 'RDC',
            status_type_nm: 'Rating Decision Complete',
            svc_type_cd: 'CP',
            temp_jrsdtn_lctn_id: '123725',
            temporary_station_of_jurisdiction: '499',
            termnl_digit_nbr: '71'
          }
      }
    end
    let(:mock_update_benefit_claim) do
      {
        return:
          { benefit_claim_record: {
              pre_dschrg_type_cd: nil
            },
            life_cycle_record: nil,
            participant_record: nil,
            return_code: 'GUIE05000',
            return_message: 'Update to Corporate was successful',
            suspence_record: nil }
      }
    end
    let(:mock_unsuccessful_update_benefit_claim) do
      {
        return:
          {
            return_code: 'GUIE05001',
            return_message: 'Update failed'
          }
      }
    end

    before do
      allow(ClaimsApi::Logger).to receive(:log)
      allow(Flipper).to receive(:enabled?).with(
        :claims_api_dependent_claimant_update_poa_relationship_fallback
      ).and_return(fallback_service_flag_enabled)
    end

    context 'when the dependent has no open claims' do
      it 'assigns the POA to the dependent via manage_ptcpnt_rlnshp' do
        VCR.use_cassette('claims_api/bgs/person_web_service/manage_ptcpnt_rlnshp_poa_no_open_claims') do
          VCR.use_cassette('claims_api/bgs/standard_data_web_service/find_poas') do
            allow(service).to receive(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp).and_call_original

            expect do
              service.assign_poa_to_dependent!
            end.not_to raise_error

            expect(service).to have_received(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)
          end
        end
      end
    end

    describe 'when claims_api_dependent_claimant_update_poa_relationship_fallback is enabled' do
      let(:fallback_service_flag_enabled) { true }
      let(:new_fallback_service) { instance_double(ClaimsApi::DependentClaimantUpdatePoaRelationshipService) }

      before do
        allow(service).to receive(:dependent_claimant_update_poa_relationship_service).and_return(new_fallback_service)
      end

      it 'uses dependent claimant update POA relationship fallback when manage_ptcpnt_rlnshp reports open claims' do
        allow(service).to receive(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)
          .and_return(:fallback_to_update_benefit_claim)
        allow(new_fallback_service).to receive(:assign_poa_to_dependent!).and_return(:success)

        expect(service.assign_poa_to_dependent!).to be_nil
        expect(new_fallback_service).to have_received(:assign_poa_to_dependent!)
      end

      it 'raises service error with new fallback reason when dependent claimant update fallback fails' do
        allow(service).to receive(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)
          .and_return(:fallback_to_update_benefit_claim)
        allow(new_fallback_service).to receive(:assign_poa_to_dependent!).and_return(:failed)

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to eq(
            'Failed to assign POA via both manage_ptcpnt_rlnshp and dependent claimant update POA relationship'
          )
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            message: poa_error_message,
            reason: 'Failed to assign POA via both manage_ptcpnt_rlnshp and dependent claimant update POA relationship'
          )
        )
      end
    end

    context 'when the dependent has open claims' do
      it 'assigns the POA to the dependent via update_benefit_claim' do
        VCR.use_cassette('claims_api/bgs/person_web_service/manage_ptcpnt_rlnshp_poa_with_open_claims') do
          VCR.use_cassette('claims_api/bgs/standard_data_web_service/find_poas') do
            allow(service).to receive(:assign_poa_to_dependent_via_update_benefit_claim).and_call_original
            allow_any_instance_of(ClaimsApi::EbenefitsBnftClaimStatusWebService).to receive(
              :find_benefit_claims_status_by_ptcpnt_id
            )
              .with(dependent_participant_id).and_return(mock_find_benefit_claims_status_by_ptcpnt_id)
            allow_any_instance_of(ClaimsApi::BenefitClaimWebService).to receive(:find_bnft_claim)
              .with(claim_id: '256009').and_return(mock_find_bnft_claim)
            allow_any_instance_of(ClaimsApi::BenefitClaimService).to receive(:update_benefit_claim)
              .and_return(mock_update_benefit_claim)

            expect do
              service.assign_poa_to_dependent!
            end.not_to raise_error

            expect(service).to have_received(:assign_poa_to_dependent_via_update_benefit_claim)
          end
        end
      end

      it 'calls find_bnft_claim_by_clmant_id when find_benefit_claims_status_by_ptcpnt_id fails' do
        VCR.use_cassette('claims_api/bgs/person_web_service/manage_ptcpnt_rlnshp_poa_with_open_claims') do
          VCR.use_cassette('claims_api/bgs/standard_data_web_service/find_poas') do
            allow(service).to receive(:assign_poa_to_dependent_via_update_benefit_claim).and_call_original
            allow_any_instance_of(ClaimsApi::EbenefitsBnftClaimStatusWebService).to receive(
              :find_benefit_claims_status_by_ptcpnt_id
            ).with(dependent_participant_id).and_return({})
            allow_any_instance_of(ClaimsApi::BenefitClaimWebService).to receive(
              :find_bnft_claim_by_clmant_id
            ).with(dependent_participant_id:).and_return(mock_find_benefit_claims_status_by_clmant_id)
            allow_any_instance_of(ClaimsApi::BenefitClaimWebService).to receive(:find_bnft_claim)
              .with(claim_id: '256009').and_return(mock_find_bnft_claim)
            allow_any_instance_of(ClaimsApi::BenefitClaimService).to receive(:update_benefit_claim)
              .and_return(mock_update_benefit_claim)

            result = service.assign_poa_to_dependent!
            expect(result).to be_nil
          end
        end
      end
    end

    context 'when handling assignment failures with Person Web Service' do
      it 'logs explicit fallback details when manage_ptcpnt_rlnshp reports open claims' do
        open_claims_error = Common::Exceptions::ServiceError.new(detail: 'PtcpntIdA has open claims.')
        person_web_service = instance_double(ClaimsApi::PersonWebService)

        allow(service).to receive_messages(person_web_service:, poa_participant_id: '600123456')
        allow(person_web_service).to receive(:manage_ptcpnt_rlnshp_poa).and_raise(open_claims_error)

        result = service.send(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)

        expect(result).to eq(:fallback_to_update_benefit_claim)
        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            reason: 'Failed to assign POA via manage_ptcpnt_rlnshp. Attempting to assign POA via update benefit claim.',
            message: 'Dependent has open claims, continuing.',
            poa_code:,
            poa_id: nil,
            level: :info
          )
        )
      end

      context 'when claims_api_dependent_claimant_update_poa_relationship_fallback is enabled' do
        let(:fallback_service_flag_enabled) { true }

        it 'logs new fallback reason details when manage_ptcpnt_rlnshp reports open claims' do
          open_claims_error = Common::Exceptions::ServiceError.new(detail: 'PtcpntIdA has open claims.')
          person_web_service = instance_double(ClaimsApi::PersonWebService)

          allow(service).to receive_messages(person_web_service:, poa_participant_id: '600123456')
          allow(person_web_service).to receive(:manage_ptcpnt_rlnshp_poa).and_raise(open_claims_error)

          result = service.send(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)

          expect(result).to eq(:fallback_to_update_benefit_claim)
          expect(ClaimsApi::Logger).to have_received(:log).with(
            'dependent_claimant_poa_assignment_service',
            hash_including(
              reason: 'Failed to assign POA via manage_ptcpnt_rlnshp. ' \
                      'Attempting to assign POA via DependentClaimantUpdatePoaRelationshipService.',
              message: 'Dependent has open claims, continuing.',
              poa_code:,
              poa_id: nil,
              level: :info
            )
          )
        end
      end

      it 'logs detailed service errors and re-raises the original exception' do
        service_error = Common::Exceptions::ServiceError.new(detail: 'Unexpected BGS service error')
        person_web_service = instance_double(ClaimsApi::PersonWebService)

        allow(service).to receive_messages(person_web_service:, poa_participant_id: '600123456')
        allow(person_web_service).to receive(:manage_ptcpnt_rlnshp_poa).and_raise(service_error)

        expect do
          service.send(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to eq 'Unexpected BGS service error'
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            message: poa_error_message,
            reason: 'Service error with Person Web Service call to assign POA via manage_ptcpnt_rlnshp'
          )
        )
      end

      it 'logs generic service error details and re-raises the original exception when no detail is provided' do
        service_error = Common::Exceptions::BackendServiceException.new
        person_web_service = instance_double(ClaimsApi::PersonWebService)

        allow(service).to receive_messages(person_web_service:, poa_participant_id: '600123456')
        allow(person_web_service).to receive(:manage_ptcpnt_rlnshp_poa).and_raise(service_error)

        expect do
          service.send(:assign_poa_to_dependent_via_manage_ptcpnt_rlnshp)
        end.to raise_error(Common::Exceptions::BackendServiceException) { |error|
          expect(error.errors.first.detail).to eq service_error.errors.first.detail
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            message: poa_error_message,
            reason: 'An unknown error occurred trying to assign POA via manage_ptcpnt_rlnshp'
          )
        )
      end
    end

    context 'when handling assignment failures with Benefit Claim Service' do
      it 'logs update failure details and raises service error when update_benefit_claim is unsuccessful' do
        allow(service).to receive_messages(
          assign_poa_to_dependent_via_manage_ptcpnt_rlnshp: :fallback_to_update_benefit_claim,
          first_open_claim_details: mock_find_bnft_claim[:bnft_claim_dto]
        )
        allow_any_instance_of(ClaimsApi::BenefitClaimService).to receive(:update_benefit_claim)
          .and_return(mock_unsuccessful_update_benefit_claim)

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(
            error.errors.first.detail
          ).to eq 'Failed to assign POA via both manage_ptcpnt_rlnshp and update benefit claim'
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            reason: 'Failed to assign POA via both manage_ptcpnt_rlnshp and update benefit claim',
            poa_code:,
            poa_id: nil,
            message: poa_error_message
          )
        )
      end

      it 'logs no-open-claim-details failure context and raises service error' do
        allow(service).to receive_messages(
          assign_poa_to_dependent_via_manage_ptcpnt_rlnshp: :fallback_to_update_benefit_claim,
          first_open_claim_details: {},
          dependent_claims: [{ phase_type: 'Complete' }]
        )

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |error|
          expect(error.errors.first.detail).to eq 'Dependent has no open claims'
        }

        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            reason: 'Dependent has no open claims',
            statuses: ['Complete']
          )
        )
      end

      it 'logs generic error class and message details and raises service error when an unexpected error occurs' do
        error = StandardError.new('Unexpected error during benefit claim update')
        allow(service).to receive_messages(
          assign_poa_to_dependent_via_manage_ptcpnt_rlnshp: :fallback_to_update_benefit_claim,
          first_open_claim_details: mock_find_bnft_claim[:bnft_claim_dto]
        )
        allow_any_instance_of(ClaimsApi::BenefitClaimService).to receive(:update_benefit_claim)
          .and_raise(error)

        expect do
          service.assign_poa_to_dependent!
        end.to raise_error(Common::Exceptions::ServiceError) { |service_error|
          expect(service_error.errors.first.detail).to eq 'Failed to assign POA via both ' \
                                                          'manage_ptcpnt_rlnshp and update benefit claim'
        }

        # generic error logging is the same for error since this is the last error raised
        expect(ClaimsApi::Logger).to have_received(:log).with(
          'dependent_claimant_poa_assignment_service',
          hash_including(
            level: :error,
            reason: 'Failed to assign POA via both manage_ptcpnt_rlnshp and update benefit claim',
            poa_code:,
            poa_id: nil,
            message: poa_error_message
          )
        )
      end
    end

    describe '#e_benefits_bnft_claim_status_web_service' do
      it 'requires the service statement' do
        res = service.send(:e_benefits_bnft_claim_status_web_service)
        expect(res).to be_a(ClaimsApi::EbenefitsBnftClaimStatusWebService)
      end
    end

    describe '#benefit_claim_web_service' do
      it 'requires the service statement' do
        res = service.send(:benefit_claim_web_service)
        expect(res).to be_a(ClaimsApi::BenefitClaimWebService)
      end
    end

    describe '#benefit_claim_service' do
      it 'requires the service statement' do
        res = service.send(:benefit_claim_service)
        expect(res).to be_a(ClaimsApi::BenefitClaimService)
      end
    end

    describe '#person_web_service' do
      it 'requires the service statement' do
        res = service.send(:person_web_service)
        expect(res).to be_a(ClaimsApi::PersonWebService)
      end
    end

    describe '#first_open_claim_details' do
      it 'collects open claims' do
        VCR.use_cassette(
          'claims_api/bgs/e_benefits_bnft_claim_status_web_service/find_benefit_claims_status_by_ptcpnt_id'
        ) do
          res = service.send(:first_open_claim_details)
          expect(res).to be_a(Hash)
          expect(res[:bnft_claim_id]).to eq('256009')
          expect(res[:bnft_claim_type_cd]).to eq('690AUTRWPMC')
        end
      end

      context 'dependent_claims does not return claims' do
        it 'finds an open claim anyway' do
          VCR.use_cassette('claims_api/bgs/benefit_claim_web_service/find_bnft_claim_by_clmant_id') do
            allow_any_instance_of(ClaimsApi::DependentClaimantPoaAssignmentService).to receive(
              :dependent_claims
            ).and_return([])
            res = service.send(:first_open_claim_details)

            expect(res[:bnft_claim_id]).to eq('600537706')
            expect(res[:bnft_claim_type_cd]).to eq('400SUPP')
          end
        end

        it 'does not find an open claim anyway' do
          allow_any_instance_of(ClaimsApi::DependentClaimantPoaAssignmentService).to receive(
            :dependent_claims
          ).and_return([])
          allow_any_instance_of(ClaimsApi::BenefitClaimWebService).to receive(
            :find_bnft_claim_by_clmant_id
          ).and_return(
            { 'xmlns:ns0': 'http://benefitclaim.services.vetsnet.vba.va.gov/', bnft_claim_dto: [[]] }
          )

          res = service.send(:first_open_claim_details)

          expect(res).to eq({})
        end
      end
    end
  end
end
