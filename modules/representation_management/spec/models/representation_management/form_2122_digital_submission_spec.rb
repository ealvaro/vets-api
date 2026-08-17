# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::Form2122DigitalSubmission, type: :model do
  describe '#normalized_limitations_of_consent' do
    context 'when record_consent is true' do
      context 'when consent_limits is empty' do
        it 'returns an empty array' do
          form = described_class.new(record_consent: true, consent_limits: [])

          expect(form.normalized_limitations_of_consent).to eq([])
        end
      end

      context 'when consent_limits is present' do
        context 'less than all limitations' do
          it 'returns the values from the allowed limitations list not in consent_limits' do
            form = described_class.new(record_consent: true, consent_limits: %w[DRUG_ABUSE HIV])

            expect(form.normalized_limitations_of_consent).to match_array(%w[ALCOHOLISM SICKLE_CELL])
          end
        end

        context 'all limitations' do
          it 'returns the an empty array' do
            allowed_list = RepresentationManagement::Form2122Base::LIMITATIONS_OF_CONSENT
            form = described_class.new(record_consent: true, consent_limits: allowed_list)

            expect(form.normalized_limitations_of_consent).to eq([])
          end
        end
      end
    end

    context 'when record_consent is false' do
      it 'returns the full allowed limitations list' do
        form = described_class.new(record_consent: false)

        allowed_list = RepresentationManagement::Form2122Base::LIMITATIONS_OF_CONSENT

        expect(form.normalized_limitations_of_consent).to match_array(allowed_list)
      end
    end
  end

  describe '#organization' do
    context 'when organization is found in AccreditedOrganization' do
      it 'returns the AccreditedOrganization' do
        accredited_organization = create(:accredited_organization, name: 'Accredited Org Name')
        form = described_class.new(organization_id: accredited_organization.poa_code)

        expect(form.organization).to eq(accredited_organization)
      end
    end

    context 'when organization is found in Veteran::Service::Organization' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:arc_appoint_a_representative_use_accredited_models).and_return(false)
      end

      it 'returns the Veteran::Service::Organization' do
        veteran_org = create(:organization, name: 'Veteran Org Name')
        form = described_class.new(organization_id: veteran_org.poa)

        expect(form.organization).to eq(veteran_org)
      end
    end

    context 'when organization is not found in either' do
      it 'returns nil' do
        form = described_class.new(organization_id: 'Nonexistent Org')

        expect(form.organization).to be_nil
      end
    end
  end

  describe 'validations' do
    subject { described_class.new(user:, dependent:, organization_id:) }

    let(:user) { create(:user, :loa3) }
    let(:dependent) { false }
    let(:organization_id) { 'ABC' }

    before do
      # Default to legacy resolution; the AccreditedX context opts into the flag explicitly.
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:arc_appoint_a_representative_use_accredited_models).and_return(false)
    end

    it { expect(subject).to validate_presence_of(:organization_id) }

    context 'organization_exists?' do
      context 'when the organization does not exist' do
        it 'adds the organization not found error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::NOT_FOUND

          expect(subject.errors[:organization]).to include(error_message)
        end
      end

      context 'when the organization exists' do
        let(:organization) { create(:organization, name: 'Veteran Org Name') }
        let(:organization_id) { organization.poa }

        it 'does not add the organization not found error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::NOT_FOUND

          expect(subject.errors[:organization]).not_to include(error_message)
        end
      end
    end

    context 'organization_accepts_digital_poa_requests?' do
      let(:organization) { create(:organization, name: 'Veteran Org Name', can_accept_digital_poa_requests:) }
      let(:organization_id) { organization.poa }

      context 'when the organization does not accept digital requests' do
        let(:can_accept_digital_poa_requests) { false }

        it 'adds the organization does not accept digital requests error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::DOES_NOT_ACCEPT_DIGITAL_REQUESTS

          expect(subject.errors[:organization]).to include(error_message)
        end
      end

      context 'when the organization accepts digital requests' do
        let(:can_accept_digital_poa_requests) { true }

        it 'does not add the organization does not accept digital requests error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::DOES_NOT_ACCEPT_DIGITAL_REQUESTS

          expect(subject.errors[:organization]).not_to include(error_message)
        end
      end
    end

    # Legacy Veteran::Service::OrganizationRepresentative join (flag off, set at the validations level).
    context 'representative_can_accept_for_organization?' do
      let(:organization) { create(:organization, name: 'Test Org', can_accept_digital_poa_requests: true) }
      let(:organization_id) { organization.poa }
      let(:rep) { create(:representative, representative_id: '12345') }

      before do
        subject.representative_id = rep.representative_id
      end

      context 'when the representative has an active any_request record' do
        before do
          create(:veteran_organization_representative,
                 representative: rep, organization:, acceptance_mode: 'any_request')
        end

        it 'does not add an error' do
          subject.valid?

          expect(subject.errors[:representative]).not_to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the representative has an active self_only record' do
        before do
          create(:veteran_organization_representative,
                 representative: rep, organization:, acceptance_mode: 'self_only')
        end

        it 'does not add an error' do
          subject.valid?

          expect(subject.errors[:representative]).not_to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the representative has an active no_acceptance record' do
        before do
          create(:veteran_organization_representative,
                 representative: rep, organization:, acceptance_mode: 'no_acceptance')
        end

        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the representative has no organization_representative record' do
        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the representative has a deactivated record' do
        before do
          create(:veteran_organization_representative,
                 representative: rep, organization:, acceptance_mode: 'any_request',
                 deactivated_at: 1.day.ago)
        end

        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the organization is not accepting digital requests' do
        let(:organization) do
          create(:organization, name: 'Test Org', can_accept_digital_poa_requests: false)
        end

        it 'skips the representative check and does not add a representative error' do
          subject.valid?

          expect(subject.errors[:representative]).not_to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end
    end

    context 'representative_can_accept_for_organization? with the appoint migration flag on (AccreditedX)' do
      let(:accredited_organization) do
        create(:accredited_organization, poa_code: 'XYZ', can_accept_digital_poa_requests: true)
      end
      let(:accredited_individual) { create(:accredited_individual, registration_number: '67890') }
      let(:organization_id) { accredited_organization.poa_code }

      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:arc_appoint_a_representative_use_accredited_models).and_return(true)
        subject.representative_id = accredited_individual.id
      end

      context 'when an active any_request accreditation exists' do
        before do
          create(:accreditation, accredited_individual:, accredited_organization:, acceptance_mode: 'any_request')
        end

        it 'does not add an error' do
          subject.valid?

          expect(subject.errors[:representative]).not_to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when an active self_only accreditation exists' do
        before do
          create(:accreditation, accredited_individual:, accredited_organization:, acceptance_mode: 'self_only')
        end

        it 'does not add an error' do
          subject.valid?

          expect(subject.errors[:representative]).not_to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the accreditation is no_acceptance' do
        before do
          create(:accreditation, accredited_individual:, accredited_organization:, acceptance_mode: 'no_acceptance')
        end

        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when no accreditation exists' do
        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end

      context 'when the accreditation is deactivated' do
        before do
          create(:accreditation, accredited_individual:, accredited_organization:,
                                 acceptance_mode: 'any_request', deactivated_at: 1.day.ago)
        end

        it 'adds an error' do
          subject.valid?

          expect(subject.errors[:representative]).to include(
            RepresentationManagement::Form2122DigitalSubmission::REP_CANNOT_ACCEPT
          )
        end
      end
    end

    context 'user_is_submitting_as_veteran?' do
      context 'when the user is not submitting as the Veteran' do
        let(:dependent) { true }

        context 'with Flipper off' do
          before do
            allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(false)
          end

          it 'adds the dependent submitter error to the form' do
            subject.valid?

            error_message = RepresentationManagement::Form2122DigitalSubmission::DEPENDENT_SUBMITTER

            expect(subject.errors[:user]).to include(error_message)
          end
        end

        context 'with Flipper on' do
          before do
            allow(Flipper).to receive(:enabled?).with(:form2122_non_veteran_digital_submit, any_args).and_return(true)
          end

          it 'does not add the dependent submitter error to the form' do
            subject.valid?

            error_message = RepresentationManagement::Form2122DigitalSubmission::DEPENDENT_SUBMITTER

            expect(subject.errors[:user]).not_to include(error_message)
          end
        end
      end

      context 'when the user is submitting as the Veteran' do
        it 'does not add the dependent submitter error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::DEPENDENT_SUBMITTER

          expect(subject.errors[:user]).not_to include(error_message)
        end
      end
    end

    context 'user_has_participant_id?' do
      context 'when the user does not have a participant id' do
        let(:user) { create(:user, participant_id: nil) }

        it 'adds the blank participant id error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::BLANK_PARTICIPANT_ID

          expect(subject.errors[:user]).to include(error_message)
        end
      end

      context 'when the user has a participant id' do
        it 'does not add the blank participant id error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::BLANK_PARTICIPANT_ID

          expect(subject.errors[:user]).not_to include(error_message)
        end
      end
    end

    context 'user_has_icn?' do
      context 'when the user does not have an ICN' do
        let(:user) { create(:user, :loa3, icn: nil) }

        it 'adds the blank ICN error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::BLANK_ICN

          expect(subject.errors[:user]).to include(error_message)
        end
      end

      context 'when the user has an ICN' do
        it 'does not add the blank ICN error to the form' do
          subject.valid?

          error_message = RepresentationManagement::Form2122DigitalSubmission::BLANK_ICN

          expect(subject.errors[:user]).not_to include(error_message)
        end
      end
    end
  end
end
