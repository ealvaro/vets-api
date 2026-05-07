# frozen_string_literal: true

require 'rails_helper'

module AccreditedRepresentativePortal # rubocop:disable Metrics/ModuleLength
  RSpec.describe PowerOfAttorneyHolderMemberships do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:accredited_representative_portal_disable_ogc_client)
        .and_return(false)
    end

    describe '#all' do
      subject(:all) { described_class.new(icn: 'some_icn', emails:).send(:all) }

      let(:emails) { [] }

      before do
        numbers = upstream_registrations.map(&:representative_id)
        expect_any_instance_of(OgcClient).to(
          receive(:find_registration_numbers_for_icn)
          .and_return(numbers)
        )
      end

      describe 'OGC returns registrations with duplicated type' do
        let(:upstream_registrations) do
          [
            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1000'
            ),
            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1001'
            )
          ]
        end

        it 'raises `Common::Exceptions::Forbidden`' do
          expect { all }.to raise_error(Common::Exceptions::Forbidden)
        end
      end

      describe 'OGC returns valid registrations' do
        let(:upstream_registrations) do
          [
            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1000',
              poa_codes: ['P10']
            ),
            create(
              :representative,
              user_types: ['claim_agents'],
              representative_id: 'R1001',
              poa_codes: ['P11']
            )
          ]
        end

        it 'returns memberships' do
          expect(all).to eq(
            [
              described_class::Membership.new(
                registration_number: 'R1000',
                power_of_attorney_holder:
                  PowerOfAttorneyHolder.new(
                    type: 'attorney',
                    name: 'Bob Law',
                    poa_code: 'P10',
                    can_accept_digital_poa_requests: false,
                    acceptance_mode: nil
                  )
              ),
              described_class::Membership.new(
                registration_number: 'R1001',
                power_of_attorney_holder:
                  PowerOfAttorneyHolder.new(
                    type: 'claims_agent',
                    name: 'Bob Law',
                    poa_code: 'P11',
                    can_accept_digital_poa_requests: false,
                    acceptance_mode: nil
                  )
              )
            ]
          )
        end
      end

      describe 'OGC returns no registrations' do
        let(:upstream_registrations) { [] }

        describe 'DB returns no registrations' do
          let(:emails) do
            [
              'nonexistent1@example.com',
              'nonexistent2@example.com'
            ]
          end

          it 'raises `Common::Exceptions::Forbidden`' do
            expect { all }.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        describe 'provided emails match registrations with duplicated types' do
          let(:emails) do
            [
              'matching1@example.com',
              'matching2@example.com'
            ]
          end

          before do
            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1000',
              email: emails.first
            )
            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1001',
              email: emails.last
            )
          end

          it 'raises `Common::Exceptions::Forbidden`' do
            expect { all }.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        describe 'provided emails match valid registration set' do
          let(:emails) do
            [
              'matching1@example.com',
              'matching2@example.com'
            ]
          end

          before do
            allow(Flipper).to receive(:enabled?)
              .with(:accredited_representative_portal_individual_accept_backend)
              .and_return(false)

            create(
              :representative,
              user_types: ['attorney'],
              representative_id: 'R1000',
              poa_codes: ['P10'],
              email: emails.first
            )
            create(
              :representative,
              user_types: ['claim_agents'],
              representative_id: 'R1001',
              poa_codes: ['P11'],
              email: emails.last
            )
            create(
              :representative,
              user_types: ['veteran_service_officer'],
              representative_id: 'R1002',
              poa_codes: %w[P12 P13],
              email: emails.last
            )

            create(:organization, poa: 'P12', name: 'Org A')
            create(:organization, poa: 'P13', name: 'Org B', can_accept_digital_poa_requests: true)

            expect_any_instance_of(OgcClient).to(
              receive(:post_icn_and_registration_combination)
              .at_least(:once)
              .and_return(put_upstream_registration_result)
            )
          end

          describe 'and write to OGC is not a conflict' do
            let(:put_upstream_registration_result) { true }

            it 'returns memberships' do
              expect(all).to eq(
                [
                  described_class::Membership.new(
                    registration_number: 'R1000',
                    power_of_attorney_holder:
                      PowerOfAttorneyHolder.new(
                        type: 'attorney',
                        name: 'Bob Law',
                        poa_code: 'P10',
                        can_accept_digital_poa_requests: false,
                        acceptance_mode: nil
                      )
                  ),
                  described_class::Membership.new(
                    registration_number: 'R1001',
                    power_of_attorney_holder:
                      PowerOfAttorneyHolder.new(
                        type: 'claims_agent',
                        name: 'Bob Law',
                        poa_code: 'P11',
                        can_accept_digital_poa_requests: false,
                        acceptance_mode: nil
                      )
                  ),
                  described_class::Membership.new(
                    registration_number: 'R1002',
                    power_of_attorney_holder:
                      PowerOfAttorneyHolder.new(
                        type: 'veteran_service_organization',
                        name: 'Org A',
                        poa_code: 'P12',
                        can_accept_digital_poa_requests: false,
                        acceptance_mode: 'no_acceptance'
                      )
                  ),
                  described_class::Membership.new(
                    registration_number: 'R1002',
                    power_of_attorney_holder:
                      PowerOfAttorneyHolder.new(
                        type: 'veteran_service_organization',
                        name: 'Org B',
                        poa_code: 'P13',
                        can_accept_digital_poa_requests: true,
                        acceptance_mode: 'no_acceptance'
                      )
                  )
                ]
              )
            end
          end

          describe 'and write to OGC is a conflict' do
            let(:put_upstream_registration_result) { :conflict }

            it 'raises `Common::Exceptions::Forbidden`' do
              expect { all }.to raise_error(Common::Exceptions::Forbidden)
            end
          end
        end
      end
    end

    context 'given a full setup' do
      let(:put_upstream_registration_result) { true }
      let(:upstream_registrations) { [] }

      let(:emails) do
        [
          'matching1@example.com',
          'matching2@example.com'
        ]
      end

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_individual_accept_backend)
          .and_return(true)

        create(
          :representative,
          user_types: ['attorney'],
          representative_id: 'R1000',
          poa_codes: ['P10'],
          email: emails.first
        )
        create(
          :representative,
          user_types: ['claim_agents'],
          representative_id: 'R1001',
          poa_codes: ['P11'],
          email: emails.last
        )
        create(
          :representative,
          user_types: ['veteran_service_officer'],
          representative_id: 'R1002',
          poa_codes: %w[P12 P13],
          email: emails.last
        )

        create(:organization, poa: 'P12', name: 'Org A')
        create(:organization, poa: 'P13', name: 'Org B', can_accept_digital_poa_requests: true)

        vso_rep = Veteran::Service::Representative.find_by(representative_id: 'R1002')
        org_a = Veteran::Service::Organization.find_by(poa: 'P12')
        create(:veteran_organization_representative,
               representative: vso_rep, organization: org_a, acceptance_mode: 'no_acceptance')

        expect_any_instance_of(OgcClient).to(
          receive(:post_icn_and_registration_combination)
          .at_least(:once)
          .and_return(put_upstream_registration_result)
        )

        numbers = upstream_registrations.map(&:representative_id)
        expect_any_instance_of(OgcClient).to(
          receive(:find_registration_numbers_for_icn)
          .and_return(numbers)
        )
      end

      describe '#registration_numbers' do
        subject(:registration_numbers) do
          memberships = described_class.new(icn: 'some_icn', emails:)
          memberships.registration_numbers
        end

        it 'returns registration_numbers' do
          expect(registration_numbers).to eq(%w[R1000 R1001 R1002])
        end
      end

      describe '#power_of_attorney_holders' do
        subject(:power_of_attorney_holders) do
          memberships = described_class.new(icn: 'some_icn', emails:)
          memberships.power_of_attorney_holders
        end

        it 'returns power_of_attorney_holders only for orgs with active org_rep records' do
          expect(power_of_attorney_holders).to eq(
            [
              PowerOfAttorneyHolder.new(
                type: 'attorney',
                name: 'Bob Law',
                poa_code: 'P10',
                can_accept_digital_poa_requests: false,
                acceptance_mode: nil
              ),
              PowerOfAttorneyHolder.new(
                type: 'claims_agent',
                name: 'Bob Law',
                poa_code: 'P11',
                can_accept_digital_poa_requests: false,
                acceptance_mode: nil
              ),
              PowerOfAttorneyHolder.new(
                type: 'veteran_service_organization',
                name: 'Org A',
                poa_code: 'P12',
                can_accept_digital_poa_requests: false,
                acceptance_mode: 'no_acceptance'
              )
            ]
          )
        end
      end

      describe '#find' do
        it 'finds the membership that matches the provided poa holder' do
          memberships = described_class.new(icn: 'some_icn', emails:)
          expect(memberships.find('P12')).to eq(
            described_class::Membership.new(
              registration_number: 'R1002',
              power_of_attorney_holder:
                PowerOfAttorneyHolder.new(
                  poa_code: 'P12',
                  type: 'veteran_service_organization',
                  name: 'Org A',
                  can_accept_digital_poa_requests: false,
                  acceptance_mode: 'no_acceptance'
                )
            )
          )
        end

        it 'returns nil for an org with no active org_rep record' do
          memberships = described_class.new(icn: 'some_icn', emails:)
          expect(memberships.find('P13')).to be_nil
        end
      end

      describe 'acceptance_mode from OrganizationRepresentative' do
        let(:vso_rep) do
          Veteran::Service::Representative.find_by(representative_id: 'R1002')
        end

        let(:org_b) { Veteran::Service::Organization.find_by(poa: 'P13') }

        context 'when OrganizationRepresentative record exists with any_request' do
          before do
            create(:veteran_organization_representative,
                   representative: vso_rep, organization: org_b, acceptance_mode: 'any_request')
          end

          it 'sets acceptance_mode to any_request' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            holder = memberships.find('P13').power_of_attorney_holder
            expect(holder.acceptance_mode).to eq('any_request')
          end
        end

        context 'when OrganizationRepresentative record exists with self_only' do
          before do
            create(:veteran_organization_representative,
                   representative: vso_rep, organization: org_b, acceptance_mode: 'self_only')
          end

          it 'sets acceptance_mode to self_only' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            holder = memberships.find('P13').power_of_attorney_holder
            expect(holder.acceptance_mode).to eq('self_only')
          end
        end

        context 'when OrganizationRepresentative record exists with no_acceptance' do
          before do
            create(:veteran_organization_representative,
                   representative: vso_rep, organization: org_b, acceptance_mode: 'no_acceptance')
          end

          it 'sets acceptance_mode to no_acceptance' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            holder = memberships.find('P13').power_of_attorney_holder
            expect(holder.acceptance_mode).to eq('no_acceptance')
          end
        end

        context 'when no OrganizationRepresentative record exists' do
          it 'excludes the organization from memberships' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            expect(memberships.find('P13')).to be_nil
          end
        end

        context 'when OrganizationRepresentative record is deactivated' do
          before do
            create(:veteran_organization_representative,
                   representative: vso_rep, organization: org_b,
                   acceptance_mode: 'any_request', deactivated_at: Time.current)
          end

          it 'excludes the organization from memberships' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            expect(memberships.find('P13')).to be_nil
          end
        end

        context 'when flag is disabled and no OrganizationRepresentative record exists' do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:accredited_representative_portal_individual_accept_backend)
              .and_return(false)
          end

          it 'still includes the organization with default acceptance_mode' do
            memberships = described_class.new(icn: 'some_icn', emails:)
            holder = memberships.find('P13').power_of_attorney_holder
            expect(holder.acceptance_mode).to eq('no_acceptance')
          end
        end
      end
    end
  end
end
