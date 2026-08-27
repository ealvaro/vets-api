# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Form526ValidationOrchestrator, type: :unit do
  let(:valid_countries) { %w[USA Canada] }

  before do
    allow_any_instance_of(described_class).to receive(:valid_countries).and_return(valid_countries)
  end

  describe '#validate' do
    context 'when form_attributes is empty' do
      it 'returns nil' do
        result = described_class.new({}).validate
        expect(result).to be_nil
      end
    end

    context 'with a valid payload' do
      it 'returns nil' do
        attrs = {
          'veteranIdentification' => {
            'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
          }
        }
        result = described_class.new(attrs).validate
        expect(result).to be_nil
      end
    end

    context 'with validation errors' do
      it 'returns the errors array' do
        attrs = {
          'veteranIdentification' => {
            'mailingAddress' => { 'country' => 'Narnia' },
            'serviceNumber' => '1234567890'
          }
        }
        result = described_class.new(attrs).validate
        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
      end
    end

    context 'with nil veteranIdentification' do
      it 'returns nil when section is blank' do
        attrs = { 'veteranIdentification' => nil }
        result = described_class.new(attrs).validate
        expect(result).to be_nil
      end
    end
  end
end
