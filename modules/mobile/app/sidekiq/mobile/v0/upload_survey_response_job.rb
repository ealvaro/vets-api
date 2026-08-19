# frozen_string_literal: true

require 'csv'
require 'sidekiq'
require 'share_point/service'

module Mobile
  module V0
    class UploadSurveyResponseJob
      include Sidekiq::Job

      STATSD_KEY_PREFIX = 'worker.mobile.v0.upload_survey_response'

      sidekiq_options(retry: 5, unique_for: 1.day)

      sidekiq_retries_exhausted do |msg, ex|
        error_class = msg['error_class'] || ex&.class&.to_s
        error_message = msg['error_message'] || ex&.message

        StatsD.increment("#{STATSD_KEY_PREFIX}.retries_exhausted")

        Rails.logger.error(
          'Mobile survey response upload retries exhausted',
          {
            job_class: msg['class'],
            jid: msg['jid'],
            error_class:,
            error_message:
          }
        )
      end

      class UploadError < StandardError; end

      SURVEY_TYPES = %w[giveFeedback].freeze

      # @param preserve_data [Boolean] When true, uploaded records are not deleted after a successful upload.
      #   Useful for dry-run/debugging scenarios. Defaults to false (records are deleted after upload).
      # @param survey_types [String, Array<String>] One or more survey types to process.
      #   Each value is matched against the `survey_type` column on Mobile::SurveyResponse.
      #   Defaults to SURVEY_TYPES, which includes all survey types to be included in the default processing.
      def perform(preserve_data: false, survey_types: SURVEY_TYPES)
        Array(survey_types).each { |survey_type| process_survey_type(survey_type, preserve_data) }
      end

      private

      def process_survey_type(survey_type, preserve_data)
        Rails.logger.info('Mobile survey response upload starting', { survey_type: })
        survey_responses = Mobile::SurveyResponse.where(survey_type:).order(:id).to_a
        response_ids = survey_responses.map(&:id)

        if response_ids.blank?
          Rails.logger.info('Mobile survey response upload skipped - no matching responses', { survey_type: })
          return
        end

        upload_survey_responses(survey_type, survey_responses, response_ids, preserve_data)
      rescue SharePoint::AuthenticationError => e
        Rails.logger.error('Mobile survey response upload authentication failed',
                           { survey_type:, error_class: e.class.name })
        raise
      rescue UploadError => e
        Rails.logger.error('Mobile survey response upload failed',
                           { survey_type:, error_class: e.class.name })
        raise
      rescue => e
        Rails.logger.error('Mobile survey response upload encountered unexpected error',
                           { survey_type:, error_class: e.class.name })
        raise
      end

      def upload_survey_responses(survey_type, survey_responses, response_ids, preserve_data)
        survey_type_snake = survey_type.to_s.underscore.gsub(/[^a-z0-9_]/, '')
        base_sharepoint_path = Settings.sharepoint.mobile_survey_storage.filepath.to_s
        sharepoint_path = [base_sharepoint_path, survey_type_snake].compact_blank.join('/')
        csv_data = build_csv_data(survey_responses)
        response = SharePoint::Service.new(sharepoint_feature: :mobile_survey_storage)
                                      .upload_csv(
                                        csv_data,
                                        sharepoint_path,
                                        "#{survey_type_snake}_#{Time.current.utc.strftime('%Y%m%d_%H%M%S%L')}.csv"
                                      )

        raise UploadError, "SharePoint upload failed with status: #{response.status}" unless response.success?

        Mobile::SurveyResponse.where(id: response_ids).delete_all unless preserve_data
        log_upload_success(survey_type, response, response_ids.size, preserve_data)
      end

      def log_upload_success(survey_type, response, count, preserve_data)
        Rails.logger.info('Mobile survey response upload succeeded',
                          {
                            survey_type:,
                            status: response.status,
                            uploaded_count: count,
                            preserve_data:
                          })
      end

      def build_csv_data(survey_responses) # rubocop:disable Metrics/MethodLength
        survey_responses_array = survey_responses
        question_keys = []
        question_fields = {}
        metadata_keys = []

        # Establish all unique question keys, their fields, and metadata keys across all survey responses
        survey_responses_array.each do |survey_response|
          survey_response.survey_data.each do |question_key, question_data|
            question_keys << question_key unless question_keys.include?(question_key)

            field_keys = question_fields[question_key] ||= []
            question_data.each_key do |field_key|
              field_keys << field_key unless field_keys.include?(field_key)
            end
          end
          survey_response.metadata&.each_key do |metadata_key|
            metadata_keys << metadata_key unless metadata_keys.include?(metadata_key)
          end
        end

        # Build CSV headers based on data above
        headers = ['uuid']
        question_keys.each do |question_key|
          question_fields[question_key].each do |field_key|
            headers << "#{question_key}_#{field_key}"
          end
        end
        metadata_keys.each { |metadata_key| headers << metadata_key }
        headers << 'submitted_at'

        CSV.generate(headers: true) do |csv|
          csv << headers
          survey_responses_array.each do |survey_response|
            row = [survey_response.user_uuid]
            survey_data_hash = survey_response.survey_data || {}

            question_keys.each do |question_key|
              question_data = survey_data_hash[question_key] || {}
              question_fields[question_key].each do |field_key|
                row << question_data[field_key]
              end
            end

            metadata_hash = survey_response.metadata || {}
            metadata_keys.each { |metadata_key| row << metadata_hash[metadata_key] }
            row << survey_response.created_at.iso8601

            csv << row
          end
        end
      end
    end
  end
end
