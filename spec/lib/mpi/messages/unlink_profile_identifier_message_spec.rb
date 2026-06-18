# frozen_string_literal: true

require 'rails_helper'
require 'mpi/messages/unlink_profile_identifier_message'

describe MPI::Messages::UnlinkProfileIdentifierMessage do
  let(:unlink_message) do
    described_class.new(icn:, identifier_type:, identifier:)
  end

  let(:icn) { 'some-icn' }
  let(:icn_with_aaid) { "#{icn}^NI^200M^USVHA^P" }
  let(:identifier) { 'some-credential-uuid' }
  let(:identifier_type) { MPI::Constants::LOGINGOV_UUID }

  describe '.perform' do
    subject { unlink_message.perform }

    shared_examples 'error response' do
      let(:expected_error) { MPI::Errors::ArgumentError }
      let(:expected_rails_log_pattern) { /\[UnlinkProfileIdentifierMessage\] Failed to build request:/ }

      it 'raises an argument error and logs an error message to rails' do
        expect(Rails.logger).to receive(:error).with(expected_rails_log_pattern)
        expect { subject }.to raise_error(expected_error)
      end
    end

    context 'when icn is not defined' do
      let(:icn) { nil }

      it_behaves_like 'error response'
    end

    context 'when identifier is not defined' do
      let(:identifier) { nil }

      it_behaves_like 'error response'
    end

    context 'when identifier_type is invalid' do
      let(:identifier_type) { 'invalid-type' }

      it_behaves_like 'error response'
    end

    shared_examples 'successfully built unlink message' do
      let(:idm_path) { 'env:Envelope/env:Body/idm:PRPA_IN201302UV02' }
      let(:subject_path) { "#{idm_path}/controlActProcess/subject" }
      let(:patient_path) { "#{subject_path}/registrationEvent/subject1/patient" }

      it 'has a USDSVA extension with a uuid' do
        expect(subject).to match_at_path("#{idm_path}/id/@extension", /200VGOV-\w{8}-\w{4}-\w{4}-\w{4}-\w{12}/)
      end

      it 'has a sender extension' do
        expect(subject).to eq_at_path("#{idm_path}/sender/device/id/@extension", '200VGOV')
      end

      it 'has a receiver extension' do
        expect(subject).to eq_at_path("#{idm_path}/receiver/device/id/@root", '1.2.840.114350.1.13.999.234')
      end

      it 'has the patient icn identifier with aaid' do
        expect(subject).to eq_at_path("#{patient_path}/id/@extension", icn_with_aaid)
      end

      it 'has a registration event with null flavor NA' do
        expect(subject).to eq_at_path("#{subject_path}/registrationEvent/id/@nullFlavor", 'NA')
      end

      it 'has a patientPerson with unlink identifier' do
        expect(subject).to eq_at_path(
          "#{patient_path}/patientPerson/asOtherIDs/id/@extension",
          formatted_identifier
        )
      end

      it 'has unlink status code in asOtherIDs' do
        expect(subject).to eq_at_path(
          "#{patient_path}/patientPerson/asOtherIDs/statusCode/@code",
          'UNLINK'
        )
      end

      it 'has scoping organization in asOtherIDs' do
        expect(subject).to eq_at_path(
          "#{patient_path}/patientPerson/asOtherIDs/scopingOrganization/id/@root",
          MPI::Constants::VA_ROOT_OID
        )
      end
    end

    context 'when logingov uuid is defined' do
      let(:identifier_type) { MPI::Constants::LOGINGOV_UUID }
      let(:formatted_identifier) do
        "#{identifier}^#{MPI::Constants::LOGINGOV_FULL_IDENTIFIER}"
      end

      it_behaves_like 'successfully built unlink message'
    end

    context 'when idme uuid is defined' do
      let(:identifier_type) { MPI::Constants::IDME_UUID }
      let(:formatted_identifier) do
        "#{identifier}^#{MPI::Constants::IDME_FULL_IDENTIFIER}"
      end

      it_behaves_like 'successfully built unlink message'
    end

    context 'when mhv uuid is defined' do
      let(:identifier_type) { MPI::Constants::MHV_UUID }
      let(:formatted_identifier) do
        "#{identifier}^#{MPI::Constants::MHV_FULL_IDENTIFIER}"
      end

      it_behaves_like 'successfully built unlink message'
    end
  end
end
