# frozen_string_literal: true

require 'rails_helper'

class FakeTokenValidationController
  include ClaimsApi::TokenValidation
end

describe FakeTokenValidationController do
  let(:controller) { FakeTokenValidationController.new }

  describe '#resolve_middle_name' do
    let(:act) { { 'middle_name' => act_middle_name } }
    let(:mpi_profile) do
      double('MPI::Response', profile: double('Profile', given_names:))
    end

    context 'when MPI has a middle name' do
      let(:given_names) { %w[James Patrick] }
      let(:act_middle_name) { nil }

      it 'returns the MPI middle name' do
        expect(controller.send(:resolve_middle_name, mpi_profile, act)).to eq('Patrick')
      end
    end

    context 'when MPI has no middle name but act does' do
      let(:given_names) { %w[James] }
      let(:act_middle_name) { 'Patrick' }

      it 'returns the act middle name' do
        expect(controller.send(:resolve_middle_name, mpi_profile, act)).to eq('Patrick')
      end

      it 'logs the fallback' do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'token_validation',
          hash_including(message: 'MPI missing middle name, using token act fallback')
        )
        controller.send(:resolve_middle_name, mpi_profile, act)
      end
    end

    context 'when neither MPI nor act has a middle name' do
      let(:given_names) { %w[James] }
      let(:act_middle_name) { nil }

      it 'returns nil' do
        expect(controller.send(:resolve_middle_name, mpi_profile, act)).to be_nil
      end
    end

    context 'when MPI returns "Null" as middle name' do
      let(:given_names) { %w[James Null] }
      let(:act_middle_name) { 'Patrick' }

      it 'returns "Null" (MPI takes priority)' do
        expect(controller.send(:resolve_middle_name, mpi_profile, act)).to eq('Null')
      end
    end
  end
end
