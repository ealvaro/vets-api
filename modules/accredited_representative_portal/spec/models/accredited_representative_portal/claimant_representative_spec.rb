# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::ClaimantRepresentative, type: :model do
  describe '.find' do
    subject(:claimant_representative) do
      described_class.find(
        claimant_icn:,
        power_of_attorney_holder_memberships:
      )
    end

    let(:claimant_icn) { '1012666182V203559' }
    let(:representative_icn) { '1234567890' }
    let(:representative_email) { 'rep@example.com' }
    let(:registration_number) { '10000' }
    let(:poa_code) { 'YHZ' }

    let(:power_of_attorney_holder_memberships) do
      AccreditedRepresentativePortal::PowerOfAttorneyHolderMemberships.new(
        icn: representative_icn,
        emails: [representative_email]
      )
    end

    let!(:organization) { create(:organization, poa: poa_code, name: 'Org Name') }

    let!(:representative) do
      create(
        :representative,
        :vso,
        representative_id: registration_number,
        poa_codes: [poa_code],
        email: representative_email
      )
    end

    let!(:representative_user_account) do
      create(:user_account, icn: representative_icn)
    end

    before do
      allow_any_instance_of(BenefitsClaims::Service).to receive(:get_power_of_attorney).and_return(
        {
          'data' => {
            'attributes' => {
              'code' => poa_code
            }
          }
        }
      )
    end

    context 'when BenefitsClaims::Service does not raise' do
      context 'and does not return poa data' do
        before do
          allow_any_instance_of(BenefitsClaims::Service).to receive(:get_power_of_attorney).and_return(
            { 'data' => { 'attributes' => {} } }
          )
        end

        it 'returns nil' do
          expect(claimant_representative).to be_nil
        end
      end

      context 'and does not return poa data or attributes' do
        before do
          allow_any_instance_of(BenefitsClaims::Service).to(
            receive(:get_power_of_attorney).and_return(
              { 'data' => {} }
            )
          )
        end

        it 'returns nil' do
          expect(subject).to be_nil
        end
      end

      context 'and returns a poa code that does not match any membership' do
        before do
          allow_any_instance_of(BenefitsClaims::Service).to receive(:get_power_of_attorney).and_return(
            {
              'data' => {
                'attributes' => {
                  'code' => 'ABC'
                }
              }
            }
          )
        end

        it 'returns nil' do
          expect(claimant_representative).to be_nil
        end
      end
    end

    context 'when BenefitsClaims::Service does raise' do
      before do
        allow_any_instance_of(BenefitsClaims::Service).to receive(:get_power_of_attorney)
          .and_raise(Common::Exceptions::ResourceNotFound.new(detail: 'not found'))
      end

      it 'raises a finder error' do
        expect { claimant_representative }
          .to raise_error(AccreditedRepresentativePortal::ClaimantRepresentative::Finder::Error)
      end
    end

    context 'when individual accept flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_individual_accept_backend)
          .and_return(false)
      end

      it 'returns a claimant representative when the claimant poa matches a membership' do
        expect(claimant_representative).to have_attributes(
          claimant_id: be_a(String),
          accredited_individual_registration_number: registration_number,
          power_of_attorney_holder: AccreditedRepresentativePortal::PowerOfAttorneyHolder.new(
            poa_code:,
            type: AccreditedRepresentativePortal::PowerOfAttorneyHolder::Types::VETERAN_SERVICE_ORGANIZATION,
            name: 'Org Name',
            can_accept_digital_poa_requests: false,
            acceptance_mode: 'no_acceptance'
          )
        )
      end
    end

    context 'when individual accept flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_individual_accept_backend)
          .and_return(true)
      end

      context 'when there is no active organization representative membership' do
        it 'returns nil' do
          expect(claimant_representative).to be_nil
        end
      end

      context 'when the organization representative membership is no_acceptance' do
        before do
          create(
            :veteran_organization_representative,
            organization_poa: poa_code,
            representative_id: registration_number,
            acceptance_mode: :no_acceptance,
            deactivated_at: nil
          )
        end

        # no_acceptance reps can still VIEW an established VSO claimant; acceptance_mode only
        # governs acting on pending requests (enforced by PowerOfAttorneyRequestPolicy).
        it 'returns a claimant representative' do
          expect(claimant_representative).to have_attributes(
            claimant_id: be_a(String),
            accredited_individual_registration_number: registration_number
          )
        end
      end

      context 'when the organization representative membership is any_request' do
        before do
          create(
            :veteran_organization_representative,
            organization_poa: poa_code,
            representative_id: registration_number,
            acceptance_mode: :any_request,
            deactivated_at: nil
          )
        end

        it 'returns a claimant representative' do
          expect(claimant_representative).to have_attributes(
            claimant_id: be_a(String),
            accredited_individual_registration_number: registration_number
          )
        end
      end

      context 'when the organization representative membership is self_only' do
        let!(:org_rep_membership) do
          create(
            :veteran_organization_representative,
            organization_poa: poa_code,
            representative_id: registration_number,
            acceptance_mode: :self_only,
            deactivated_at: nil
          )
        end

        # The claimant already has an accepted POA held by the rep's org (the BenefitsClaims
        # stub returns the org's poa_code). Once a POA is accepted it belongs to the whole
        # org, so a self_only rep can view the established claimant whether or not they were
        # the rep named in 16A on the request.
        context 'when the rep is named in 16A on a request for the claimant' do
          let!(:claimant_user_account) do
            create(:user_account, icn: claimant_icn)
          end

          let!(:poa_request) do
            create(
              :power_of_attorney_request,
              claimant: claimant_user_account,
              poa_code:,
              accredited_individual: representative
            )
          end

          it 'returns a claimant representative' do
            expect(claimant_representative).to have_attributes(
              claimant_id: be_a(String),
              accredited_individual_registration_number: registration_number
            )
          end
        end

        context 'when the rep is not named in 16A on any request for the claimant' do
          it 'returns a claimant representative' do
            expect(claimant_representative).to have_attributes(
              claimant_id: be_a(String),
              accredited_individual_registration_number: registration_number
            )
          end
        end

        context 'when a request for the claimant names a different representative' do
          let!(:claimant_user_account) do
            create(:user_account, icn: claimant_icn)
          end

          let!(:different_representative) do
            create(
              :representative,
              :vso,
              representative_id: '99999',
              poa_codes: [poa_code],
              email: 'other-rep@example.com'
            )
          end

          before do
            create(
              :power_of_attorney_request,
              claimant: claimant_user_account,
              poa_code:,
              accredited_individual: different_representative
            )
          end

          it 'still returns a claimant representative for the established POA' do
            expect(claimant_representative).to have_attributes(
              claimant_id: be_a(String),
              accredited_individual_registration_number: registration_number
            )
          end
        end
      end
    end
  end
end
