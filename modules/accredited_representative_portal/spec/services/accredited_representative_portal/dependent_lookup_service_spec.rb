# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::DependentLookupService do
  let(:dependent_lookup_service) { described_class.new(veteran:) }
  let(:veteran) do
    {
      first_name: 'Wesley',
      last_name: 'Ford',
      ssn: '123456789',
      birth_date: '1988-02-10'
    }
  end
  let(:mpi_service) { instance_double(MPI::Service) }
  let(:mpi_profile) { build(:mpi_profile) }

  describe 'initialize' do
    context 'when some arguments are blank' do
      before do
        veteran[:first_name] = ''
        veteran[:ssn] = ''
      end

      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran:)
        end.to raise_error(ArgumentError, 'Arguments cannot be blank')
      end
    end

    context 'when Veteran birth_date does not follow YYYY-MM-DD format' do
      before { veteran[:birth_date] = '02-10-1988' }

      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran:)
        end.to raise_error(ArgumentError, 'Veteran birth_date must follow the YYYY-MM-DD format')
      end
    end

    context 'when Veteran ssn does not follow a 9-digit format' do
      before { veteran[:ssn] = '12345' }

      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran:)
        end.to raise_error(ArgumentError, 'Veteran ssn must be a 9-digit string')
      end
    end

    it 'assigns the instance variables' do
      service = described_class.new(veteran:)

      expect(service.instance_variable_get(:@veteran_first_name)).to eq('Wesley')
      expect(service.instance_variable_get(:@veteran_last_name)).to eq('Ford')
      expect(service.instance_variable_get(:@veteran_ssn)).to eq('123456789')
      expect(service.instance_variable_get(:@veteran_birth_date)).to eq('1988-02-10')
    end
  end

  describe '#dependents_for_veteran' do
    let(:bgs_services) { instance_double(BGS::Services) }
    let(:claimant_service) { instance_double(BGS::ClaimantWebService) }
    let(:single_dependent_response) do
      {
        number_of_records: '1',
        persons: { award_indicator: 'Y',
                   date_of_birth: '07/09/2024',
                   email_address: nil,
                   first_name: 'TESTER',
                   gender: 'M',
                   last_name: 'TEST',
                   proof_of_dependency: 'N',
                   participant_id: '123456789',
                   related_to_vet: 'Y',
                   relationship: 'Child',
                   ssn: '123456789',
                   veteran_indicator: 'N' },
        return_code: 'SHAR 9999',
        return_message: 'Records found'
      }
    end

    context 'when the Veteran profile cannot be found' do
      it 'raises a RecordNotFound error' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: nil)
        )
        expect { dependent_lookup_service.dependents_for_veteran }
          .to raise_error(Common::Exceptions::RecordNotFound)
      end
    end

    context 'when a Veteran participant ID is not returned in the profile response' do
      let(:mpi_profile_no_participant_id) { build(:mpi_profile, participant_id: nil) }

      it 'raises a ResourceNotFound error' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile_no_participant_id)
        )
        expect { dependent_lookup_service.dependents_for_veteran }
          .to raise_error(Common::Exceptions::ResourceNotFound)
      end
    end

    it 'returns the Veteran\'s dependents' do
      allow(MPI::Service).to receive(:new).and_return(mpi_service)
      expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
        OpenStruct.new(profile: mpi_profile)
      )

      VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
        response = dependent_lookup_service.dependents_for_veteran

        expect(response).to be_an(Array)
        expect(response.length).to eq(2)

        expect(response[0][:ptcpnt_id]).to eq('601684665')
        expect(response[0][:first_name]).to eq('JANE')
        expect(response[0][:last_name]).to eq('MOORE')
        expect(response[0][:date_of_birth]).to eq('01/01/2015')

        expect(response[1][:ptcpnt_id]).to eq('600849397')
        expect(response[1][:first_name]).to eq('MILLY')
        expect(response[1][:last_name]).to eq('LOW')
        expect(response[1][:date_of_birth]).to eq('01/18/1996')
      end
    end

    context 'when BGS responds with a hash rather than an array (only one dependent)' do
      it 'returns an array' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        allow(BGS::Services).to receive(:new).and_return(bgs_services)
        expect(bgs_services).to receive(:claimant).and_return(claimant_service)
        expect(claimant_service).to receive(:find_dependents_by_participant_id)
          .and_return(single_dependent_response.deep_dup)

        response = dependent_lookup_service.dependents_for_veteran

        expect(response).to be_an(Array)
        expect(response.length).to eq(1)

        expect(response[0][:ssn]).to eq('123456789')
        expect(response[0][:first_name]).to eq('TESTER')
        expect(response[0][:last_name]).to eq('TEST')
        expect(response[0][:date_of_birth]).to eq('07/09/2024')
      end
    end

    context 'when the Veteran has no dependents' do
      it 'returns an empty array' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        allow(BGS::Services).to receive(:new).and_return(bgs_services)
        expect(bgs_services).to receive(:claimant).and_return(claimant_service)
        expect(claimant_service).to receive(:find_dependents_by_participant_id)
          .and_return([])

        response = dependent_lookup_service.dependents_for_veteran

        expect(response).to be_an(Array)
        expect(response).to be_empty
      end
    end
  end

  describe 'public methods' do
    let(:dependent) do
      {
        first_name: 'Milly',
        last_name: 'Low',
        icn: '1013469511V725621',
        birth_date: '1996-01-18'
      }
    end
    let(:dependent_participant_id) { '600849397' }
    let(:mpi_service) { instance_double(MPI::Service) }
    let(:dependent_mpi_profile) { build(:mpi_profile, participant_id: dependent_participant_id) }

    context 'when the dependent participant ID matches a dependent record' do
      before do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        expect(mpi_service).to receive(:find_profile_by_identifier).and_return(
          OpenStruct.new(profile: dependent_mpi_profile)
        )
      end

      it '#dependent_relationship_established? returns true' do
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent:)

          expect(response).to be(true)
        end
      end

      it '#log_dependent_relationship_state does not log any missing info to StatsD' do
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).not_to receive(:track_count)
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end
      end
    end

    context 'when the dependent participant ID does not match any dependent records' do
      let(:dependent_participant_id) { '123456789' }

      before do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        expect(mpi_service).to receive(:find_profile_by_identifier).and_return(
          OpenStruct.new(profile: dependent_mpi_profile)
        )
      end

      it '#dependent_relationship_established? returns false' do
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent:)

          expect(response).to be(false)
        end
      end

      it "#log_dependent_relationship_state logs 'relationship not established' to StatsD" do
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_relationship_not_established')
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).not_to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_participant_id_not_found')
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).not_to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_profile_not_found')
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end
      end
    end

    context 'when some arguments are blank' do
      before do
        dependent[:first_name] = ''
        dependent[:icn] = ''
      end

      it '#dependent_relationship_established? raises an ArgumentError' do
        expect do
          dependent_lookup_service.dependent_relationship_established?(dependent:)
        end.to raise_error(ArgumentError, 'Arguments cannot be blank')
      end

      it '#log_dependent_relationship_state raises an ArgumentError' do
        expect do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end.to raise_error(ArgumentError, 'Arguments cannot be blank')
      end
    end

    context 'when dependent birth_date does not follow YYYY-MM-DD format' do
      before { dependent[:birth_date] = '02-10-1988' }

      it '#dependent_relationship_established? raises an ArgumentError' do
        expect do
          dependent_lookup_service.dependent_relationship_established?(dependent:)
        end.to raise_error(ArgumentError, 'Dependent birth_date must follow the YYYY-MM-DD format')
      end

      it '#log_dependent_relationship_state raises an ArgumentError' do
        expect do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end.to raise_error(ArgumentError, 'Dependent birth_date must follow the YYYY-MM-DD format')
      end
    end

    context 'when dependent icn does not follow the icn format' do
      before { dependent[:icn] = '12345' }

      it '#dependent_relationship_established? raises an ArgumentError' do
        expect do
          dependent_lookup_service.dependent_relationship_established?(dependent:)
        end.to raise_error(ArgumentError, 'Dependent icn does not match expected format')
      end

      it '#log_dependent_relationship_state raises an ArgumentError' do
        expect do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end.to raise_error(ArgumentError, 'Dependent icn does not match expected format')
      end
    end

    it '#dependent_relationship_established? assigns the instance variables' do
      allow(MPI::Service).to receive(:new).and_return(mpi_service)
      expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
        OpenStruct.new(profile: mpi_profile)
      )
      expect(mpi_service).to receive(:find_profile_by_identifier).and_return(
        OpenStruct.new(profile: dependent_mpi_profile)
      )

      VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
        service = dependent_lookup_service

        service.dependent_relationship_established?(dependent:)

        expect(service.instance_variable_get(:@dependent_first_name)).to eq('Milly')
        expect(service.instance_variable_get(:@dependent_last_name)).to eq('Low')
        expect(service.instance_variable_get(:@dependent_icn)).to eq('1013469511V725621')
        expect(service.instance_variable_get(:@dependent_birth_date)).to eq('1996-01-18')
      end
    end

    context 'when the dependent profile cannot be found' do
      before do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        expect(mpi_service).to receive(:find_profile_by_identifier).and_return(
          OpenStruct.new(profile: nil)
        )
      end

      it '#dependent_relationship_established? successfully falls back to matching on first name, last name, and dob' do
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent:)

          expect(response).to be(true)
        end
      end

      it "#log_dependent_relationship_state logs 'profile missing' and 'participant id missing' to StatsD" do
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_participant_id_not_found')
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_profile_not_found')
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end
      end

      context 'when there is no first name, last name, and dob match' do
        before do
          dependent[:first_name] = 'No'
          dependent[:last_name] = 'Match'
        end

        it '#dependent_relationship_established? returns false' do
          VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
            response = dependent_lookup_service.dependent_relationship_established?(dependent:)

            expect(response).to be(false)
          end
        end
      end
    end

    context 'when a dependent participant ID is not returned in the profile response' do
      let(:mpi_profile_no_participant_id) { build(:mpi_profile, participant_id: nil) }

      before do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )
        expect(mpi_service).to receive(:find_profile_by_identifier).and_return(
          OpenStruct.new(profile: mpi_profile_no_participant_id)
        )
      end

      it '#dependent_relationship_established? successfully falls back to matching on first name, last name, and dob' do
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent:)

          expect(response).to be(true)
        end
      end

      it "#log_dependent_relationship_state logs 'participant id missing' to StatsD" do
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_participant_id_not_found')
        expect_any_instance_of(AccreditedRepresentativePortal::Monitoring).not_to receive(:track_count)
          .with('ar.services.dependent_lookup_service.dependent_profile_not_found')
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          dependent_lookup_service.log_dependent_relationship_state(dependent:)
        end
      end

      context 'when there is no first name, last name, and dob match' do
        before do
          dependent[:first_name] = 'No'
          dependent[:last_name] = 'Match'
        end

        it '#dependent_relationship_established? returns false' do
          VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
            response = dependent_lookup_service.dependent_relationship_established?(dependent:)

            expect(response).to be(false)
          end
        end
      end
    end
  end
end
