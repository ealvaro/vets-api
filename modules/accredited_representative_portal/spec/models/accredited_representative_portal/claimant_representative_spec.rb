# frozen_string_literal: true

require 'rails_helper'
require_relative '../../support/poa_holder_fixtures'

module AccreditedRepresentativePortal # rubocop:disable Metrics/ModuleLength
  RSpec.describe ClaimantRepresentative, type: :model do
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

      shared_examples 'claimant representative finder' do
        let!(:organization) { create_holder_organization(poa_code:, name: 'Org Name') }

        let!(:representative) do
          create_holder_registration(
            type: :vso,
            registration_number:,
            poa_codes: [poa_code],
            email: representative_email
          )
        end

        let!(:representative_user_account) do
          create(:user_account, icn: representative_icn)
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

        context 'when there is no active organization representative membership' do
          it 'returns nil' do
            expect(claimant_representative).to be_nil
          end
        end

        context 'when the organization representative membership is no_acceptance' do
          before do
            create_holder_acceptance(registration_number:, poa_code:, acceptance_mode: 'no_acceptance')
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
            create_holder_acceptance(registration_number:, poa_code:, acceptance_mode: 'any_request')
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
            create_holder_acceptance(registration_number:, poa_code:, acceptance_mode: 'self_only')
          end

          context 'when there is a matching non-withdrawn POA request for the claimant' do
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

          context 'when there is no matching POA request for the claimant' do
            let!(:different_claimant_user_account) do
              create(:user_account, icn: '1008596379V859838')
            end

            before do
              create(
                :power_of_attorney_request,
                claimant: different_claimant_user_account,
                poa_code:,
                accredited_individual: representative
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
                create_holder_registration(
                  type: :vso,
                  registration_number: '99999',
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

      # Attorneys and claims agents hold POA as individuals — they have no organization and therefore
      # no OrganizationRepresentative / Accreditation record. Reaching the finder means the claimant's
      # established POA code already matches the rep's own poa_code, so they must be able to VIEW the
      # claimant. Regression #28447 applied the org-membership check to every holder type and wrongly
      # excluded them.
      shared_examples 'individual holder claimant representative' do
        let!(:representative_user_account) do
          create(:user_account, icn: representative_icn)
        end

        %i[attorney claims_agent].each do |holder_type|
          context "when the representative is a #{holder_type} holding the claimant's POA" do
            let!(:representative) do
              create_holder_registration(
                type: holder_type,
                registration_number:,
                poa_codes: [poa_code],
                email: representative_email
              )
            end

            it 'returns a claimant representative without an organization membership' do
              expect(claimant_representative).to have_attributes(
                claimant_id: be_a(String),
                accredited_individual_registration_number: registration_number
              )
            end
          end
        end
      end

      context 'with legacy models' do
        include_context 'with legacy poa holders'
        include_examples 'claimant representative finder'
        include_examples 'individual holder claimant representative'
      end

      context 'with accredited models' do
        include_context 'with accredited poa holders'
        include_examples 'claimant representative finder'
        include_examples 'individual holder claimant representative'
      end
    end

    describe 'Finder#allowed_for_claimant?' do
      # Fail closed: the allow-list must deny any holder type that is not one of the known VSO /
      # attorney / claims-agent types, rather than defaulting to allowed.
      it 'denies a membership whose holder type is unrecognized' do
        holder = PowerOfAttorneyHolder.new(
          type: 'something_unexpected',
          poa_code: 'YHZ',
          name: 'Mystery Holder',
          can_accept_digital_poa_requests: false,
          acceptance_mode: nil
        )
        membership = PowerOfAttorneyHolderMemberships::Membership.new(
          registration_number: '10000',
          power_of_attorney_holder: holder
        )
        finder = described_class::Finder.new(
          claimant_icn: '1012666182V203559',
          power_of_attorney_holder_memberships: nil
        )

        expect(finder.send(:allowed_for_claimant?, membership)).to be(false)
      end
    end
  end
end
