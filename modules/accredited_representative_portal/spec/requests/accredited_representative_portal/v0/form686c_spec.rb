# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe AccreditedRepresentativePortal::V0::Form686cController, type: :request do
  let(:icn) { '1234567890V123456' }
  let(:veteran_temp_id) { AccreditedRepresentativePortal::IcnTemporaryIdentifier.save_icn(icn).id }
  let(:representative_user) { create(:representative_user, email: 'rep@va.gov') }

  let(:mpi_profile) do
    build(
      :mpi_profile,
      icn:,
      given_names: %w[Jane Q],
      family_name: 'Claimant',
      birth_date: '1985-05-05',
      ssn: '123456789',
      participant_id: '600100100'
    )
  end
  let(:mpi_service) { instance_double(MPI::Service) }

  let(:form_data) do
    {
      'view:selectable686_options': { add_spouse: true },
      dependents_application: {
        veteran_contact_information: {
          veteran_address: {
            country_name: 'USA',
            address_line1: '123 Main St',
            city: 'Portland',
            state_code: 'ME',
            zip_code: '04101'
          }
        },
        spouse_information: {
          full_name: { first: 'Spouse', last: 'Claimant' },
          ssn: '987654321',
          birth_date: '1986-06-06'
        }
      }
    }
  end

  let(:submit_params) { form_data.merge(veteranTempId: veteran_temp_id, formId: '21-686c-ARP') }

  let!(:representative_in_progress_form) do
    create(
      :representative_in_progress_form,
      rep_user_account: representative_user.user_account,
      veteran_icn: icn,
      form_id: '21-686c-ARP'
    )
  end

  before do
    login_as(representative_user)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:accredited_representative_portal_killswitch).and_return(false)
    allow(MPI::Service).to receive(:new).and_return(mpi_service)
    allow(mpi_service).to receive(:find_profile_by_identifier)
      .and_return(create(:find_profile_response, profile: mpi_profile))
  end

  describe '#dependents' do
    context 'when feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:accredited_representative_portal_submit_686c_v2).and_return(false)
      end

      it 'returns a 404 error' do
        get '/accredited_representative_portal/v0/form686c/dependents',
            params: { veteranTempId: veteran_temp_id }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:accredited_representative_portal_submit_686c_v2).and_return(true)
      end

      context 'when veteranTempId does not resolve to a claimant' do
        it 'returns a 404 error' do
          get '/accredited_representative_portal/v0/form686c/dependents',
              params: { veteranTempId: 'bogus' }

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the rep does not hold POA for the claimant' do
        before do
          allow_any_instance_of(described_class)
            .to receive(:authorize).with(icn, policy_class: AccreditedRepresentativePortal::FormSubmissionPolicy)
            .and_raise(Pundit::NotAuthorizedError)
        end

        it 'returns a 403 error' do
          expect(BGS::DependentService).not_to receive(:new)

          get '/accredited_representative_portal/v0/form686c/dependents',
              params: { veteranTempId: veteran_temp_id }

          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when BGS::DependentService throws an error' do
        before do
          allow_any_instance_of(described_class)
            .to receive(:authorize).with(
              icn, policy_class: AccreditedRepresentativePortal::FormSubmissionPolicy
            ) do |controller, *|
              controller.instance_variable_set(:@_pundit_policy_authorized, true)
              true
            end
        end

        it 'returns an empty array' do
          VCR.use_cassette('bgs/claimant_web_service/dependents_400') do
            get '/accredited_representative_portal/v0/form686c/dependents',
                params: { veteranTempId: veteran_temp_id }
          end

          expect(response.body).to eq '[]'
        end
      end

      context 'when the rep holds POA for the claimant' do
        let(:expected_response) do
          [
            {
              fullName: {
                first: 'JANE',
                middle: 'M',
                last: 'WEBB',
                suffix: nil
              },
              dateOfBirth: '1960-01-02',
              ssn: '222883214',
              relationshipToVeteran: 'Spouse',
              awardIndicator: 'N'
            },
            {
              fullName: {
                first: 'MARK',
                middle: nil,
                last: 'WEBB',
                suffix: nil
              },
              dateOfBirth: '2002-02-04',
              ssn: nil,
              relationshipToVeteran: 'Child',
              awardIndicator: 'N'
            }
          ]
        end

        before do
          allow_any_instance_of(described_class)
            .to receive(:authorize).with(
              icn, policy_class: AccreditedRepresentativePortal::FormSubmissionPolicy
            ) do |controller, *|
              controller.instance_variable_set(:@_pundit_policy_authorized, true)
              true
            end
        end

        it 'returns dependent information in correct format' do
          VCR.use_cassette('bgs/claimant_web_service/dependents') do
            get '/accredited_representative_portal/v0/form686c/dependents',
                params: { veteranTempId: veteran_temp_id }
          end

          expect(JSON.parse(response.body, symbolize_names: true)).to eq expected_response
        end
      end
    end
  end
end
