# frozen_string_literal: true

require_relative 'base_formatter'

module Forms
  module SubmissionStatuses
    module Formatters
      class Hca1010EzFormatter < BaseFormatter
        private

        def merge_record(submission_map, api_status)
          status_record = OpenStruct.new(
            id: api_status[:id],
            form_type: '10-10EZ',
            status: api_status[:status],
            created_at: parse_date(api_status[:created_at]),
            updated_at: parse_date(api_status[:updated_at])
          )
          submission_map[0] = status_record
        end

        def build_submissions_map(_submissions)
          {}
        end

        def parse_date(date_string)
          return nil if date_string.nil?

          begin
            Time.zone.parse(date_string)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
