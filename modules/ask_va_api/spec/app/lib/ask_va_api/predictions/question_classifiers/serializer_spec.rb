# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Predictions::QuestionClassifiers::Serializer do
  describe '#call' do
    let(:snake_case_data) do
      {
        'model_name' => 'Category',
        'model_version' => 2,
        'predictions' => {
          '1' => {
            'confidence_level' => 92,
            'name' => 'Education benefits and work study',
            'model_id' => 1,
            'category' => {
              'id' => 1,
              'name' => 'Education benefits and work study',
              'description' => 'Questions about education benefits'
            }
          },
          '2' => {
            'confidence_level' => 6,
            'name' => 'Vocational rehabilitation',
            'model_id' => 2,
            'category' => {
              'id' => 2,
              'name' => 'Vocational rehabilitation',
              'description' => 'Questions about vocational rehabilitation'
            }
          },
          '3' => {
            'confidence_level' => 2,
            'name' => 'Health care',
            'model_id' => 3
          }
        }
      }
    end

    context 'with complete prediction data' do
      it 'transforms snake_case to camelCase' do
        serializer = described_class.new(snake_case_data)
        result = serializer.call

        expect(result[:modelName]).to eq('Category')
        expect(result[:modelVersion]).to eq(2)
      end

      it 'transforms prediction fields to camelCase' do
        serializer = described_class.new(snake_case_data)
        result = serializer.call

        expect(result[:predictions]['1'][:confidenceLevel]).to eq(92)
        expect(result[:predictions]['1'][:modelId]).to eq(1)
      end

      it 'transforms category fields to camelCase' do
        serializer = described_class.new(snake_case_data)
        result = serializer.call

        category = result[:predictions]['1'][:category]
        expect(category[:id]).to eq(1)
        expect(category[:name]).to eq('Education benefits and work study')
        expect(category[:description]).to eq('Questions about education benefits')
      end

      it 'handles missing category field' do
        serializer = described_class.new(snake_case_data)
        result = serializer.call

        expect(result[:predictions]['3'][:category]).to be_nil
      end

      it 'includes all three prediction ranks' do
        serializer = described_class.new(snake_case_data)
        result = serializer.call

        expect(result[:predictions].keys).to contain_exactly('1', '2', '3')
      end
    end

    context 'with error response' do
      let(:error_data) do
        {
          'model_name' => 'Category',
          'model_version' => 2,
          'error' => 'Invalid input: question too short'
        }
      end

      it 'includes error field in response' do
        serializer = described_class.new(error_data)
        result = serializer.call

        expect(result[:error]).to eq('Invalid input: question too short')
      end
    end

    context 'with blank data' do
      it 'returns nil for nil input' do
        serializer = described_class.new(nil)
        result = serializer.call

        expect(result).to be_nil
      end

      it 'returns empty hash for empty hash input' do
        serializer = described_class.new({})
        result = serializer.call

        expect(result).to eq({})
      end
    end

    context 'with sparse predictions' do
      let(:sparse_data) do
        {
          'model_name' => 'Category',
          'model_version' => 2,
          'predictions' => {
            '1' => {
              'confidence_level' => 95,
              'name' => 'Benefits',
              'model_id' => 1
            }
          }
        }
      end

      it 'only transforms provided predictions' do
        serializer = described_class.new(sparse_data)
        result = serializer.call

        expect(result[:predictions].keys).to contain_exactly('1')
      end
    end
  end
end
