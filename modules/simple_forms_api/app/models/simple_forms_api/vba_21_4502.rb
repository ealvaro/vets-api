# frozen_string_literal: true

require 'simple_forms_api/overflow_4502'

module SimpleFormsApi
  class VBA214502 < BaseForm
    STATS_KEY = 'api.simple_forms_api.21_4502'
    FORM_NUMBER = '21-4502'

    include ::PdfFill::Forms::FormHelper

    def initialize(data)
      super
      @data = extract_payload(data)
    end

    def metadata
      mailing_address = @data['current_mailing_address']
      {
        'veteranFirstName' => @data.dig('full_name', 'first'),
        'veteranLastName' => @data.dig('full_name', 'last'),
        'fileNumber' => @data['va_file_number'].presence || @data['ssn'],
        'zipCode' => mailing_address&.dig('postal_code'),
        'source' => 'VA Platform Digital Forms',
        'docType' => doc_type,
        'businessLine' => 'CMP'
      }
    end

    def doc_type
      if Flipper.enabled?(:simple_forms_s3_mms_prefix_bugfix)
        "StructuredData:#{@data['form_number'].presence || FORM_NUMBER}"
      else
        @data['form_number'].presence || FORM_NUMBER
      end
    end

    def notification_first_name
      @data.dig('full_name', 'first')
    end

    def notification_email_address
      @data['email']
    end

    def zip_code_is_us_based
      mailing_address = @data['current_mailing_address']
      country = mailing_address&.dig('country')
      %w[US USA].include?(country)
    end

    def desired_stamps
      signature_text = @data['statement_of_truth_signature']
      coords = [[50, 46]]

      [{ coords:, text: signature_text, page: 0 }]
    end

    def submission_date_stamps(_timestamp = Time.current.in_time_zone('America/Chicago'))
      []
    end

    def track_user_identity(confirmation_number)
      identity = driver? ? 'driver' : 'passenger'
      StatsD.increment("#{STATS_KEY}.#{identity}")
      Rails.logger.info('Simple forms api - 21-4502 submission user identity', identity:, confirmation_number:)
    end

    def driver?
      ActiveModel::Type::Boolean.new.cast(@data['veteran_will_operate_vehicle']) || false
    end

    def overflow_pdf
      return nil if [nil, ''].include?(@data['veteran_will_operate_vehicle'])

      Overflow4502.new(data, cutoff: 1).generate
    end

    private

    def normalize_keys(data)
      return data unless @data.is_a?(Hash)

      @data.deep_transform_keys { |key| key.to_s.underscore }
    end

    def extract_payload(data)
      data = data&.to_unsafe_h unless @data.is_a?(Hash)
      return data unless @data.is_a?(Hash)

      payload = @data.dig('automobile_adaptive_claim', 'form') || @data['automobile_adaptive_claim'] || data
      return payload unless payload.is_a?(String)

      JSON.parse(payload)
    rescue JSON::ParserError
      Rails.logger.info('SimpleFormsApi::VBA214502 payload parse failed')
      payload
    end

    def date_part(field, part)
      # frontend submits as YYYY-MM-DD
      if @data[field].is_a?(String)
        date = split_date(@data[field])
        return date.nil? ? '' : date[part]
      end

      # otherwise development api submissions could be different
      value = @data[field]
      return value[part] if value.is_a?(Hash)

      if value.is_a?(Array)
        index = { 'year' => 0, 'month' => 1, 'day' => 2 }[part]
        return value[index] if index
      end

      if value.respond_to?(:strftime)
        return value.strftime('%Y') if part == 'year'
        return value.strftime('%m') if part == 'month'
        return value.strftime('%d') if part == 'day'
      end

      nil
    end

    public :date_part
  end
end
