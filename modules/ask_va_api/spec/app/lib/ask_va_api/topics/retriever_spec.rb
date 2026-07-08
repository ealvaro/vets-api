# frozen_string_literal: true

require 'rails_helper'

module AskVAApi
  module Topics
    RSpec.describe Retriever do
      let(:parsed_data) do
        { Topics: [{ Id: 1, Name: 'Topic A', ParentId: 'cat-1', RankOrder: 0 },
                   { Id: 2, Name: 'Topic B', ParentId: 'cat-1', RankOrder: 0 },
                   { Id: 3, Name: 'Other Topic', ParentId: 'cat-2', RankOrder: 0 }] }
      end
      let(:static_data_service) { instance_double(Crm::CacheData) }
      let(:entity_class) { Entity }
      let(:parent_id) { '75524deb-d864-eb11-bb24-000d3a579c45' }

      describe '#call' do
        let(:retriever) { described_class.new(parent_id:, user_mock_data:, entity_class:) }

        context 'when using mock data' do
          let(:user_mock_data) { true }
          let(:response) { retriever.call }

          it 'reads from a file and returns an array of Entity instances' do
            expect(response).to all(be_a(entity_class))
          end

          it 'returns only items with the matching parent_id' do
            expect(response.map(&:parent_id).uniq).to eq([parent_id])
          end

          it 'returns items with topic_type Topic' do
            expect(response.map(&:topic_type).uniq).to eq(['Topic'])
          end

          it 'returns items sorted by rank_order' do
            rank_orders = response.map(&:rank_order)
            expect(rank_orders).to eq(rank_orders.sort)
          end
        end

        context 'when not using mock data' do
          let(:user_mock_data) { false }

          context 'when the Topics key is blank' do
            before do
              allow(Crm::CacheData).to receive(:new).and_return(static_data_service)
              allow(static_data_service).to receive(:call).and_return({ Topics: [] })
            end

            it 'returns an empty array' do
              expect(retriever.call).to eq([])
            end
          end

          context 'when successful' do
            let(:parent_id) { 'cat-1' }

            before do
              allow(Crm::CacheData).to receive(:new).and_return(static_data_service)
              allow(static_data_service).to receive(:call).and_return(parsed_data)
            end

            it 'fetches data using Crm::CacheData service and returns an array of Entity instances' do
              expect(retriever.call).to all(be_a(entity_class))
            end
          end

          context 'when sorting with RankOrder values present' do
            let(:parent_id) { 'cat-1' }
            let(:parsed_data) do
              { Topics: [{ Id: 1, Name: 'Zebra', ParentId: 'cat-1', RankOrder: 1 },
                         { Id: 2, Name: 'Apple', ParentId: 'cat-1', RankOrder: 2 },
                         { Id: 3, Name: 'Other Topic', ParentId: 'cat-2', RankOrder: 1 }] }
            end

            before do
              allow(Crm::CacheData).to receive(:new).and_return(static_data_service)
              allow(static_data_service).to receive(:call).and_return(parsed_data)
            end

            it 'sorts by RankOrder as the primary sort key' do
              expect(retriever.call.map(&:rank_order)).to eq([1, 2])
            end

            it 'does not fall back to Name when all RankOrder values are present' do
              expect(retriever.call.map(&:name)).to eq(%w[Zebra Apple])
            end
          end

          context 'when any RankOrder value is nil' do
            let(:parent_id) { 'cat-1' }
            let(:parsed_data) do
              { Topics: [{ Id: 1, Name: 'Banana', ParentId: 'cat-1', RankOrder: 2 },
                         { Id: 2, Name: 'Apple', ParentId: 'cat-1', RankOrder: nil },
                         { Id: 3, Name: 'Cherry', ParentId: 'cat-1', RankOrder: 1 }] }
            end

            before do
              allow(Crm::CacheData).to receive(:new).and_return(static_data_service)
              allow(static_data_service).to receive(:call).and_return(parsed_data)
            end

            it 'falls back to sorting by Name' do
              expect(retriever.call.map(&:name)).to eq(%w[Apple Banana Cherry])
            end
          end

          context 'when an error occurs during data retrieval' do
            let(:body) do
              '{"Data":null,"Message":"Data Validation: null ,"ExceptionOccurred":' \
                'true,"ExceptionMessage":"Data Validation: null","MessageId": "6dfa81bd-f04a-4f39-88c5-1422d88ed3ff"}'
            end
            let(:failure) { Faraday::Response.new(response_body: body, status: 400) }

            before do
              allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('token')
              allow_any_instance_of(Crm::Service).to receive(:call)
                .with(endpoint: 'Topics', payload: {}).and_return(failure)
            end

            it 'rescues the error and calls the ErrorHandler' do
              expect { retriever.call }.to raise_error(ErrorHandler::ServiceError)
            end
          end
        end
      end
    end
  end
end
