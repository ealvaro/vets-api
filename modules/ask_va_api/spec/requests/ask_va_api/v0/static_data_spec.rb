# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AskVAApi StaticData', type: :request do
  let(:logger) { instance_double(LogService) }
  let(:span) { instance_double(Datadog::Tracing::Span) }

  before do
    allow(LogService).to receive(:new).and_return(logger)
    allow(logger).to receive(:call).and_yield(span)
    allow(span).to receive(:set_tag)
    allow(span).to receive(:set_error)
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('token')
  end

  shared_examples_for 'common error handling' do |status, action, error_message|
    it 'logs and renders error and sets datadog tags' do
      expect(response).to have_http_status(status)
      expect(JSON.parse(response.body)['error']).to eq(error_message)
      expect(logger).to have_received(:call).with(action)
      expect(span).to have_received(:set_tag).with('error', true)
      expect(span).to have_received(:set_tag).with('error.msg', error_message)
      expect(Rails.logger).to have_received(:error).with("Error during #{action}: #{error_message}")
    end
  end

  describe 'GET #categories' do
    let(:categories_path) { '/ask_va_api/v0/categories' }
    let(:expected_hash) do
      { 'id' => '75524deb-d864-eb11-bb24-000d3a579c45',
        'type' => 'categories',
        'attributes' =>
         { 'name' => 'Education benefits and work study',
           'allow_attachments' => true,
           'description' => nil,
           'display_name' => 'Education benefits and work study',
           'parent_id' => nil,
           'rank_order' => 1,
           'requires_authentication' => true,
           'topic_type' => 'Category',
           'contact_preferences' => ['Email'] } }
    end

    context 'when successful' do
      before do
        get categories_path, params: { user_mock_data: true }
      end

      it 'returns categories data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user_mock_data is the string "false"' do
      let(:cache_data) { instance_double(Crm::CacheData) }
      let(:parsed_data) do
        { Topics: [{ Id: '75524deb-d864-eb11-bb24-000d3a579c45', Name: 'Education benefits and work study',
                     ParentId: nil, Description: nil, RequiresAuthentication: true, AllowAttachments: true,
                     RankOrder: 1, DisplayName: 'Education benefits and work study', TopicType: 'Category',
                     ContactPreferences: ['Email'] }] }
      end

      before do
        allow(Crm::CacheData).to receive(:new).and_return(cache_data)
        allow(cache_data).to receive(:call).and_return(parsed_data)
        get categories_path, params: { user_mock_data: 'false' }
      end

      it 'casts to boolean false and fetches from CRM cache instead of mock data' do
        expect(cache_data).to have_received(:call)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Crm::CacheData)
          .to receive(:call)
          .and_raise(StandardError)
        get categories_path
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end

  describe 'GET #topics' do
    let(:topics_path) { '/ask_va_api/v0/categories/75524deb-d864-eb11-bb24-000d3a579c45/topics' }
    let(:expected_hash) do
      { 'id' => '1b2b8586-e764-eb11-bb23-000d3a579c3f',
        'type' => 'topics',
        'attributes' =>
         { 'name' => 'Benefits for survivors and dependents',
           'allow_attachments' => true,
           'description' => nil,
           'display_name' => 'Benefits for survivors and dependents',
           'parent_id' => '75524deb-d864-eb11-bb24-000d3a579c45',
           'rank_order' => 0,
           'requires_authentication' => true,
           'topic_type' => 'Topic',
           'contact_preferences' => ['Email'] } }
    end

    context 'when successful' do
      before do
        get topics_path, params: { user_mock_data: true }
      end

      it 'returns topics data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Crm::CacheData)
          .to receive(:call)
          .and_raise(StandardError)
        get topics_path
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end

  describe 'GET #subtopics' do
    let(:subtopics_path) { '/ask_va_api/v0/topics/152b8586-e764-eb11-bb23-000d3a579c3f/subtopics' }
    let(:expected_hash) do
      { 'id' => '952dbcee-eb64-eb11-bb23-000d3a579b83',
        'type' => 'subtopics',
        'attributes' =>
         { 'name' => 'Application',
           'allow_attachments' => true,
           'description' => nil,
           'display_name' => 'Application',
           'parent_id' => '152b8586-e764-eb11-bb23-000d3a579c3f',
           'rank_order' => 0,
           'requires_authentication' => false,
           'topic_type' => 'SubTopic',
           'contact_preferences' => ['Email'] } }
    end

    context 'when successful' do
      before do
        get subtopics_path, params: { user_mock_data: true }
      end

      it 'returns subtopics data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Crm::CacheData)
          .to receive(:call)
          .and_raise(StandardError)
        get subtopics_path
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end

  describe 'GET #contents' do
    let(:contents_path) { '/ask_va_api/v0/contents' }
    let(:expected_hash) do
      { 'id' => '75524deb-d864-eb11-bb24-000d3a579c45',
        'type' => 'contents',
        'attributes' =>
         { 'name' => 'Education benefits and work study',
           'allow_attachments' => true,
           'description' => nil,
           'display_name' => 'Education benefits and work study',
           'parent_id' => nil,
           'rank_order' => 1,
           'requires_authentication' => true,
           'topic_type' => 'Category',
           'contact_preferences' => ['Email'] } }
    end

    context 'when successful' do
      before do
        get contents_path, params: { user_mock_data: true, type: 'category' }
      end

      it 'returns contents data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'service error' }

      before do
        allow_any_instance_of(Crm::CacheData)
          .to receive(:call)
          .and_raise(StandardError)
        get contents_path, params: { type: 'category' }
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end
end
