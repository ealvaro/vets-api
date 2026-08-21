# frozen_string_literal: true

require 'rails_helper'
require_relative '../../lib/ivc_champva/monitor'

RSpec.describe IvcChampva::MPIService do
  let(:service) { described_class.new }
  let(:mock_mpi_service) { instance_double(MPI::Service) }
  let(:mock_monitor) { instance_double(IvcChampva::Monitor) }

  let(:form_data) do
    JSON.parse(Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'form_json', 'vha_10_10d.json').read)
  end

  let(:successful_mpi_response) do
    instance_double(MPI::Responses::FindProfileResponse, ok?: true,
                                                         profile: instance_double(MPI::Models::MviProfile,
                                                                                  icn: '12345678901234567890'))
  end

  before do
    allow(MPI::Service).to receive(:new).and_return(mock_mpi_service)
    allow(IvcChampva::Monitor).to receive(:new).and_return(mock_monitor)
  end

  after do
    # Clear RSpec mocks to prevent pollution of subsequent tests
    RSpec::Mocks.space.proxy_for(MPI::Service).reset
    RSpec::Mocks.space.proxy_for(IvcChampva::Monitor).reset
  end

  describe '#validate_profiles' do
    context 'when MPI profiles are found' do
      before do
        allow(mock_mpi_service).to receive(:find_profile_by_attributes).and_return(successful_mpi_response)
        allow(mock_monitor).to receive(:track_mpi_profile_found)
      end

      it 'calls MPI service for veteran and each applicant' do
        # Expect calls for the veteran and 5 applicants from fixture
        expect(mock_mpi_service).to receive(:find_profile_by_attributes).exactly(6).times
        service.validate_profiles(form_data)
      end

      it 'tracks successful profile finds' do
        expect(mock_monitor).to receive(:track_mpi_profile_found).exactly(6).times
        service.validate_profiles(form_data)
      end
    end

    context 'when MPI profiles are not found' do
      let(:modified_form_data) do
        # Use form data but with invalid SSNs to trigger not found responses
        form_data.tap do |data|
          data['veteran']['ssn_or_tin'] = '000000000'
          data['applicants'].each { |applicant| applicant['applicant_ssn'] = '000000000' }
        end
      end

      before do
        allow(mock_mpi_service).to receive(:find_profile_by_attributes)
          .and_raise(MPI::Errors::RecordNotFound.new('No matching records found'))
        allow(mock_monitor).to receive(:track_mpi_profile_not_found)
      end

      it 'tracks profile not found events when MPI raises RecordNotFound' do
        expect(mock_monitor).to receive(:track_mpi_profile_not_found).exactly(6).times
        service.validate_profiles(modified_form_data)
      end
    end

    context 'when MPI service has errors' do
      before do
        allow(mock_mpi_service).to receive(:find_profile_by_attributes)
          .and_raise(MPI::Errors::FailedRequestError.new('Service unavailable'))
        allow(mock_monitor).to receive(:track_mpi_service_error)
      end

      it 'tracks service error events' do
        expect(mock_monitor).to receive(:track_mpi_service_error).exactly(6).times
        service.validate_profiles(form_data)
      end
    end

    context 'with invalid data' do
      it 'handles nil form data gracefully' do
        expect { service.validate_profiles(nil) }.not_to raise_error
      end

      it 'handles empty form data gracefully' do
        expect { service.validate_profiles({}) }.not_to raise_error
      end
    end

    context 'date formatting' do
      let(:veteran_with_mm_dd_yyyy_date) do
        {
          'veteran' => {
            'full_name' => { 'first' => 'John', 'last' => 'Doe' },
            'date_of_birth' => '02-15-1987', # MM-DD-YYYY format
            'ssn_or_tin' => '123456789'
          }
        }
      end

      before do
        allow(mock_mpi_service).to receive(:find_profile_by_attributes).and_return(successful_mpi_response)
        allow(mock_monitor).to receive(:track_mpi_profile_found)
      end

      it 'converts MM-DD-YYYY date format to YYYY-MM-DD when calling MPI service' do
        expect(mock_mpi_service).to receive(:find_profile_by_attributes).with(
          first_name: 'John',
          last_name: 'Doe',
          birth_date: '1987-02-15', # Should be converted to YYYY-MM-DD
          ssn: '123456789'
        )

        service.validate_profiles(veteran_with_mm_dd_yyyy_date)
      end

      it 'reads applicant SSN from applicant_ssn rather than ssn_or_tin' do
        applicant_data = {
          'applicants' => [
            {
              'applicant_name' => { 'first' => 'Jane', 'last' => 'Smith' },
              'applicant_dob' => '1990-05-01',
              'applicant_ssn' => '987654321',
              'ssn_or_tin' => '111111111'
            }
          ]
        }

        expect(mock_mpi_service).to receive(:find_profile_by_attributes).with(
          first_name: 'Jane',
          last_name: 'Smith',
          birth_date: '1990-05-01',
          ssn: '987654321'
        )

        service.validate_profiles(applicant_data)
      end
    end
  end

  describe '#lookup_name_by_icn' do
    let(:icn) { '0000001200581123V296649000000' }
    let(:mock_profile) do
      instance_double(MPI::Models::MviProfile, given_names: %w[Jane M], family_name: 'Doe')
    end
    let(:successful_response) { instance_double(MPI::Responses::FindProfileResponse, ok?: true, profile: mock_profile) }

    context 'when the profile is found' do
      before { allow(mock_mpi_service).to receive(:find_profile_by_identifier).and_return(successful_response) }

      it 'returns first and last name' do
        result = service.lookup_name_by_icn(icn)
        expect(result[:first_name]).to eq('Jane')
        expect(result[:last_name]).to eq('Doe')
      end

      it 'calls MPI with the ICN identifier type' do
        expect(mock_mpi_service).to receive(:find_profile_by_identifier).with(
          identifier: icn,
          identifier_type: MPI::Constants::ICN
        )
        service.lookup_name_by_icn(icn)
      end
    end

    context 'when the profile is not found' do
      before do
        allow(mock_mpi_service).to receive(:find_profile_by_identifier)
          .and_raise(MPI::Errors::RecordNotFound.new('not found'))
        allow(mock_monitor).to receive(:track_mpi_profile_not_found)
      end

      it 'returns nil' do
        expect(service.lookup_name_by_icn(icn)).to be_nil
      end

      it 'tracks the not found event' do
        expect(mock_monitor).to receive(:track_mpi_profile_not_found).with('icn_lookup', anything)
        service.lookup_name_by_icn(icn)
      end
    end

    context 'when MPI service errors' do
      before do
        allow(mock_mpi_service).to receive(:find_profile_by_identifier)
          .and_raise(MPI::Errors::FailedRequestError.new('service unavailable'))
        allow(mock_monitor).to receive(:track_mpi_service_error)
      end

      it 'returns nil' do
        expect(service.lookup_name_by_icn(icn)).to be_nil
      end

      it 'tracks the service error' do
        expect(mock_monitor).to receive(:track_mpi_service_error).with('icn_lookup', anything)
        service.lookup_name_by_icn(icn)
      end
    end
  end
end
