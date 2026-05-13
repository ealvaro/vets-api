# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::SurveyResponse, type: :model do
  describe 'validations' do
    let(:valid_survey_data) do
      {
        'q01' => {
          'type' => 'free_response',
          'label' => 'Explain your issue',
          'value' => 'This is my response'
        }
      }
    end

    let(:valid_attributes) do
      {
        survey_type: 'giveFeedback',
        user_uuid: SecureRandom.uuid,
        survey_data: valid_survey_data,
        metadata: { 'os' => 'iOS', 'version' => '15.0' }
      }
    end

    it 'is valid with valid attributes' do
      survey_response = described_class.new(valid_attributes)
      expect(survey_response).to be_valid
    end

    it 'requires survey_type' do
      survey_response = described_class.new(valid_attributes.except(:survey_type))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_type]).to include('can\'t be blank')
    end

    it 'requires user_uuid' do
      survey_response = described_class.new(valid_attributes.except(:user_uuid))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:user_uuid]).to include('can\'t be blank')
    end

    it 'requires survey_data' do
      survey_response = described_class.new(valid_attributes.except(:survey_data))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('can\'t be blank')
    end
  end

  describe 'survey_type validation' do
    it 'accepts valid survey_type' do
      survey_response = described_class.new(survey_type: 'giveFeedback')
      expect(survey_response.survey_type).to eq('giveFeedback')
    end

    it 'rejects invalid survey_type' do
      survey_response = described_class.new(
        survey_type: 'invalid_type',
        user_uuid: SecureRandom.uuid,
        survey_data: { 'q01' => { 'type' => 'test', 'label' => 'test', 'value' => 'test' } }
      )
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_type]).to include('is not included in the list')
    end

    it 'accepts all valid survey types' do
      Mobile::SurveyResponse::VALID_SURVEY_TYPES.each do |survey_type|
        survey_response = described_class.new(survey_type:)
        survey_response.valid?
        expect(survey_response.errors[:survey_type]).to be_empty
      end
    end
  end

  describe 'survey_data validation' do
    let(:base_attributes) do
      {
        survey_type: 'giveFeedback',
        user_uuid: SecureRandom.uuid,
        metadata: { 'os' => 'iOS', 'version' => '15.0' }
      }
    end

    it 'validates survey_data structure with all required fields' do
      survey_data = {
        'q01' => {
          'type' => 'free_response',
          'label' => 'Question label',
          'value' => 'Answer value'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).to be_valid
    end

    it 'allows additional fields in survey_data objects' do
      survey_data = {
        'q01' => {
          'type' => 'multiple_choice',
          'label' => 'Question label',
          'value' => '3',
          'color' => 'blue',
          'extra_field' => 'extra_value'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).to be_valid
    end

    it 'requires type field in survey_data objects' do
      survey_data = {
        'q01' => {
          'label' => 'Question label',
          'value' => 'Answer value'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 missing required fields: type')
    end

    it 'requires label field in survey_data objects' do
      survey_data = {
        'q01' => {
          'type' => 'free_response',
          'value' => 'Answer value'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 missing required fields: label')
    end

    it 'requires value field in survey_data objects' do
      survey_data = {
        'q01' => {
          'type' => 'free_response',
          'label' => 'Question label'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 missing required fields: value')
    end

    it 'requires multiple missing fields in survey_data objects' do
      survey_data = {
        'q01' => {
          'type' => 'free_response'
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 missing required fields: label, value')
    end

    it 'requires survey_data to be an object' do
      survey_response = described_class.new(base_attributes.merge(survey_data: 'not an object'))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('must be an object')
    end

    it 'requires survey_data to be an object when given an array' do
      survey_response = described_class.new(base_attributes.merge(survey_data: %w[not an object]))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('must be an object')
    end

    it 'requires survey_data question values to be objects' do
      survey_data = {
        'q01' => 'not an object'
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 must be an object')
    end

    it 'continues validation for other questions when one question value is invalid' do
      survey_data = {
        'q01' => 'not an object',
        'q02' => {
          'type' => 'free_response'
          # missing label and value
        }
      }
      survey_response = described_class.new(base_attributes.merge(survey_data:))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:survey_data]).to include('question q01 must be an object')
      expect(survey_response.errors[:survey_data]).to include('question q02 missing required fields: label, value')
    end
  end

  describe 'metadata validation' do
    let(:base_attributes) do
      {
        survey_type: 'giveFeedback',
        user_uuid: SecureRandom.uuid,
        survey_data: {
          'q01' => {
            'type' => 'free_response',
            'label' => 'Question label',
            'value' => 'Answer value'
          }
        }
      }
    end

    it 'allows metadata with any object structure' do
      metadata = { 'foo' => 'bar', 'baz' => 123 }
      survey_response = described_class.new(base_attributes.merge(metadata:))
      expect(survey_response).to be_valid
    end

    it 'allows metadata to be nil' do
      survey_response = described_class.new(base_attributes.merge(metadata: nil))
      expect(survey_response).to be_valid
    end

    it 'allows metadata to be an empty object' do
      survey_response = described_class.new(base_attributes.merge(metadata: {}))
      expect(survey_response).to be_valid
    end

    it 'rejects metadata that is not an object (string)' do
      survey_response = described_class.new(base_attributes.merge(metadata: 'not an object'))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:metadata]).to include('must be an object')
    end

    it 'rejects metadata that is not an object (array)' do
      survey_response = described_class.new(base_attributes.merge(metadata: %w[not an object]))
      expect(survey_response).not_to be_valid
      expect(survey_response.errors[:metadata]).to include('must be an object')
    end
  end
end
