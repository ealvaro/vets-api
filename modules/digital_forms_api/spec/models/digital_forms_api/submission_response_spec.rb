# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DigitalFormsApi::SubmissionResponse do
  subject(:submission_response) { described_class.new(response) }

  # Mirrors the OpenStruct(body:) shape the Submissions service returns (see the controller specs).
  let(:response) { OpenStruct.new(body:) }

  describe '#veteran_id' do
    context 'when the envelope carries a veteranId' do
      let(:body) do
        { 'envelope' => { 'veteranId' => { 'identifierType' => 'PARTICIPANTID', 'value' => '12345' } } }
      end

      it 'returns the raw veteranId object from the envelope' do
        expect(submission_response.veteran_id).to eq('identifierType' => 'PARTICIPANTID', 'value' => '12345')
      end
    end

    context 'when the veteranId is a non-Hash value' do
      let(:body) { { 'envelope' => { 'veteranId' => 'not-a-hash' } } }

      it 'returns it unchanged (auth logic decides what to do with it)' do
        expect(submission_response.veteran_id).to eq('not-a-hash')
      end
    end

    context 'when the envelope has no veteranId' do
      let(:body) { { 'envelope' => {} } }

      it 'returns nil' do
        expect(submission_response.veteran_id).to be_nil
      end
    end
  end

  describe '#payload' do
    context 'when the envelope carries a payload' do
      let(:body) do
        { 'envelope' => { 'payload' => { 'veteranInformation' => { 'fullName' => { 'first' => 'John' } } } } }
      end

      it 'returns the form payload from the envelope' do
        expect(submission_response.payload).to eq('veteranInformation' => { 'fullName' => { 'first' => 'John' } })
      end
    end

    context 'when the envelope has no payload' do
      let(:body) { { 'envelope' => {} } }

      it 'returns nil' do
        expect(submission_response.payload).to be_nil
      end
    end
  end

  context 'when the envelope key is absent entirely' do
    let(:body) { {} }

    it 'returns nil for both accessors' do
      expect(submission_response.veteran_id).to be_nil
      expect(submission_response.payload).to be_nil
    end
  end
end
