# frozen_string_literal: true

module AskVAApi
  module Topics
    class Retriever < BaseRetriever
      def initialize(parent_id:, **args)
        super(**args)
        @parent_id = parent_id
      end

      private

      def fetch_data
        data = user_mock_data ? static_data : fetch_from_cache
        filter_data(data)
      end

      def static_data
        @static_data ||= begin
          static = File.read('modules/ask_va_api/config/locales/static_data.json')
          JSON.parse(static, symbolize_names: true)
        end
      end

      def fetch_from_cache
        Crm::CacheData.new.call(endpoint: 'Topics', cache_key: 'categories_topics_subtopics')
      end

      def filter_data(data)
        return [] if data[:Topics].blank?

        topics = data[:Topics].select { |topic| topic[:ParentId] == @parent_id }
        sort_by_rank_order_or_name(topics)
      end
    end
  end
end
