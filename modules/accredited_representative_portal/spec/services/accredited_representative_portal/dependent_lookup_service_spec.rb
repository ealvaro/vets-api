# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::DependentLookupService do
  describe 'initialize' do
    context 'when some arguments are blank' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran_first_name: '',
                              veteran_last_name: 'Ford',
                              veteran_ssn: '',
                              veteran_birth_date: '1988-02-10')
        end.to raise_error(ArgumentError, 'Arguments cannot be blank')
      end
    end

    context 'when veteran_birth_date does not follow YYYY-MM-DD format' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran_first_name: 'Wesley',
                              veteran_last_name: 'Ford',
                              veteran_ssn: '123456789',
                              veteran_birth_date: '02-10-1988')
        end.to raise_error(ArgumentError, 'veteran_birth_date must follow the YYYY-MM-DD format')
      end
    end

    context 'when veteran_ssn does not follow a 9-digit format' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(veteran_first_name: 'Wesley',
                              veteran_last_name: 'Ford',
                              veteran_ssn: '12345',
                              veteran_birth_date: '1988-02-10')
        end.to raise_error(ArgumentError, 'SSN must be a 9-digit string')
      end
    end

    it 'assigns the instance variables' do
      service = described_class.new(veteran_first_name: 'Wesley',
                                    veteran_last_name: 'Ford',
                                    veteran_ssn: '123456789',
                                    veteran_birth_date: '1988-02-10')

      expect(service.instance_variable_get(:@veteran_first_name)).to eq('Wesley')
      expect(service.instance_variable_get(:@veteran_last_name)).to eq('Ford')
      expect(service.instance_variable_get(:@veteran_ssn)).to eq('123456789')
      expect(service.instance_variable_get(:@veteran_birth_date)).to eq('1988-02-10')
    end

    it 'removes hyphens from the veteran_ssn before saving it' do
      service = described_class.new(veteran_first_name: 'Wesley',
                                    veteran_last_name: 'Ford',
                                    veteran_ssn: '123-45-6789',
                                    veteran_birth_date: '1988-02-10')

      expect(service.instance_variable_get(:@veteran_ssn)).to eq('123456789')
    end
  end

  describe '#dependents_for_veteran' do
    let(:dependent_lookup_service) do
      described_class.new(veteran_first_name: 'Wesley',
                          veteran_last_name: 'Ford',
                          veteran_ssn: '123456789',
                          veteran_birth_date: '1988-02-10')
    end
    let(:mpi_service) { instance_double(MPI::Service) }
    let(:mpi_profile) { build(:mpi_profile) }
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

    it 'returns the Veteran\'s dependents that have an awardIndicator == \'Y\'' do
      allow(MPI::Service).to receive(:new).and_return(mpi_service)
      expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
        OpenStruct.new(profile: mpi_profile)
      )

      VCR.use_cassette('bgs/claimant_web_service/dependents_one_awarded') do
        response = dependent_lookup_service.dependents_for_veteran

        expect(response).to be_an(Array)
        expect(response.length).to eq(1)

        expect(response[0][:award_indicator]).to eq('Y')
        expect(response[0][:ssn]).to eq('222883214')
        expect(response[0][:first_name]).to eq('JANE')
        expect(response[0][:last_name]).to eq('WEBB')
        expect(response[0][:date_of_birth]).to eq('01/02/1960')
      end
    end

    context 'when all dependents have an awardIndicator == \'N\'' do
      it 'returns an empty array' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )

        VCR.use_cassette('bgs/claimant_web_service/dependents') do
          response = dependent_lookup_service.dependents_for_veteran

          expect(response).to be_an(Array)
          expect(response).to be_empty
        end
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

        expect(response[0][:award_indicator]).to eq('Y')
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

  describe '#dependent_relationship_established?' do
    let(:dependent_lookup_service) do
      described_class.new(veteran_first_name: 'Wesley',
                          veteran_last_name: 'Ford',
                          veteran_ssn: '123456789',
                          veteran_birth_date: '1988-02-10')
    end
    let(:mpi_service) { instance_double(MPI::Service) }
    let(:mpi_profile) { build(:mpi_profile) }

    context 'when the dependent_ssn matches a dependent record' do
      let(:dependent_ssn) { '222883214' }

      it 'returns true' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )

        VCR.use_cassette('bgs/claimant_web_service/dependents_one_awarded') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent_ssn)

          expect(response).to be(true)
        end
      end
    end

    context 'when the dependent_ssn does not match any dependent records' do
      let(:dependent_ssn) { '123456789' }

      it 'returns false' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )

        VCR.use_cassette('bgs/claimant_web_service/dependents_one_awarded') do
          response = dependent_lookup_service.dependent_relationship_established?(dependent_ssn)

          expect(response).to be(false)
        end
      end
    end

    context 'when dependent_ssn is blank' do
      it 'raises an ArgumentError' do
        expect do
          dependent_lookup_service.dependent_relationship_established?('')
        end.to raise_error(ArgumentError, 'dependent_ssn is required')
      end
    end

    context 'when dependent_ssn does not follow a 9-digit format' do
      it 'raises an ArgumentError' do
        expect do
          dependent_lookup_service.dependent_relationship_established?('12345')
        end.to raise_error(ArgumentError, 'SSN must be a 9-digit string')
      end
    end

    context 'when the dependent_ssn argument contains hyphens' do
      let(:ssn_with_hyphens) { '222-88-3214' }

      it 'removes the hyphens before comparing the SSN to the dependents list' do
        allow(MPI::Service).to receive(:new).and_return(mpi_service)
        expect(mpi_service).to receive(:find_profile_by_attributes).and_return(
          OpenStruct.new(profile: mpi_profile)
        )

        VCR.use_cassette('bgs/claimant_web_service/dependents_one_awarded') do
          response = dependent_lookup_service.dependent_relationship_established?(ssn_with_hyphens)

          expect(response).to be(true)
        end
      end
    end
  end
end
