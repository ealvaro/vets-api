# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/clear/code_container'

describe SignIn::Clear::CodeContainer do
  let(:code_container) { described_class.new(state:, code_verifier:) }
  let(:state) { 'some-state' }
  let(:code_verifier) { 'some-code-verifier' }

  describe 'validations' do
    describe '#state' do
      context 'when state is present' do
        it 'is valid' do
          expect(code_container).to be_valid
        end
      end

      context 'when state is nil' do
        let(:state) { nil }

        it 'is not valid' do
          expect(code_container).not_to be_valid
          expect(code_container.errors[:state]).to include("can't be blank")
        end
      end
    end
  end

  describe 'attributes' do
    it 'stores and retrieves the state and code_verifier' do
      code_container.save!
      found = described_class.find(state)

      expect(found.state).to eq(state)
      expect(found.code_verifier).to eq(code_verifier)
    end
  end
end
