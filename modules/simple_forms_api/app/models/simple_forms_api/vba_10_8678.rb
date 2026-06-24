# frozen_string_literal: true

require 'hexapdf'
require 'simple_forms_api/overflow_108678'

module SimpleFormsApi
  class VBA108678 < BaseForm
    STATS_KEY = 'api.simple_forms_api.10_8678'
    FORM_NUMBER = '10-8678'
    CHECK_BOX_COORDINATES = [
      {
        upper_checkbox: [313.5, 304.0],
        upper_left_radio: [313.5, 291.5],
        upper_right_radio: [361.5, 291.5],
        lower_checkbox: [451.5, 304.0],
        lower_left_radio: [451.5, 291.5],
        lower_right_radio: [499.5, 291.5]
      }.freeze,
      {
        upper_checkbox: [313.5, 268.0],
        upper_left_radio: [313.5, 255.5],
        upper_right_radio: [361.5, 255.5],
        lower_checkbox: [451.5, 268.0],
        lower_left_radio: [451.5, 255.5],
        lower_right_radio: [499.5, 255.5]
      }.freeze,
      {
        upper_checkbox: [313.5, 232.0],
        upper_left_radio: [313.5, 219.5],
        upper_right_radio: [361.5, 219.5],
        lower_checkbox: [451.5, 232.0],
        lower_left_radio: [451.5, 219.5],
        lower_right_radio: [499.5, 219.5]
      }.freeze,
      {
        upper_checkbox: [313.5, 196.0],
        upper_left_radio: [313.5, 183.5],
        upper_right_radio: [361.5, 183.5],
        lower_checkbox: [451.5, 196.0],
        lower_left_radio: [451.5, 183.5],
        lower_right_radio: [499.5, 183.5]
      }.freeze
    ].freeze
    attr_reader :address, :appliances_for_pdf

    include ::PdfFill::Forms::FormHelper

    def initialize(data)
      super

      @address = FormEngine::Address.new(
        address_line1: data.dig('address', 'street'),
        address_line2: data.dig('address', 'street2'),
        city: data.dig('address', 'city'),
        state_code: data.dig('address', 'state'),
        zip_code: data.dig('address', 'postal_code')
      )
      @appliances_for_pdf = map_appliances
    end

    def full_address
      "#{@address.address_line1 || ''}, #{@address.address_line2 || ''}, #{@address.city || ''}, #{@address.state_code || ''} #{@address.zip_code || ''}" # rubocop:disable Layout/LineLength
    end

    def name_for_pdf
      "#{last_name}, #{first_name}, #{middle_initial}"
    end

    # Full Name Methods
    def first_name
      data.dig('full_name', 'first') || ''
    end

    def middle_initial
      data.dig('full_name', 'middle') || ''
    end

    def last_name
      data.dig('full_name', 'last') || ''
    end

    def zip_code_is_us_based
      %w[USA US].include?(data.dig('address', 'country')&.strip&.upcase)
    end

    def notification_first_name
      first_name
    end

    def notification_last_name
      last_name
    end

    # SSN split for PDF fields
    def last_four_ssn
      return '' if data['ssn'].nil?

      ssn = split_ssn(data['ssn'])
      ssn['third']
    end

    def notification_email_address
      data['email'].presence || data['email_address'].presence
    end

    # Signature
    def signature
      data['statement_of_truth_signature'] || data['veteran_signature']
    end

    # Appliances / Prosthetics
    def appliances
      data['appliances'] || []
    end

    # Metadata for logging
    def metadata
      {
        'veteranFirstName' => first_name,
        'veteranLastName' => last_name,
        'zipCode' => address.zip_code,
        'fileNumber' => data['va_file_number'].presence || data['ssn'],
        'source' => 'VA Platform Digital Forms',
        'docType' => doc_type,
        'businessLine' => 'CMP'
      }
    end

    def doc_type
      if Flipper.enabled?(:simple_forms_s3_mms_prefix_bugfix)
        "StructuredData:#{data['form_number'].presence || FORM_NUMBER}"
      else
        data['form_number'].presence || FORM_NUMBER
      end
    end

    # Format appliances for PDF
    def map_appliances
      return [] if appliances.empty?

      appliances.map do |app|
        {
          device: app['device_or_medication'],
          disability: app['service_connected_disability'],
          impacted_locations: extract_button_list(app['impacted_locations'])
        }
      end
    end

    def desired_stamps
      []
    end

    def submission_date_stamps(time_stamp)
      [
        {
          coords: [10, 780],
          text: "Application Submitted: #{time_stamp}",
          page: 0,
          font_size: 12
        }
      ]
    end

    # needs to respond to `.empty?`
    def overflow_pdf
      return nil if data['appliances'].blank?

      devices_list = data['appliances']
      return nil if devices_list.blank?

      Overflow108678.new(devices_list, cutoff: 1).generate
    end

    # Due to a bug in the PDF we cannot select the Upper or Lower checkboxes,
    # this method manually writes a "X" to the pdf in the correct spots.
    def manual_fills(pdf_path)
      return pdf_path if @appliances_for_pdf.empty?

      begin
        coords = check_box_coordinates
        temp_path = "#{pdf_path}.modified.pdf"
        doc = HexaPDF::Document.open(pdf_path)
        canvas = doc.pages[0].canvas(type: :overlay)
        canvas.save_graphics_state do
          # loop through items and draw a "X" in the checkbox
          @appliances_for_pdf.each_with_index do |item, idx|
            next if idx > 3

            draw_impacted_location_marks(canvas, coords[idx], item[:impacted_locations])
          end
        end
        # returns a Hexapdf doc, so use string for path reference
        doc.write(temp_path, optimize: true)
        # overwrite old pdf with new markings
        FileUtils.mv(temp_path, pdf_path)
        # delete old pdf
        Common::FileHelpers.delete_file_if_exists(temp_path)
        pdf_path
      rescue => e
        Rails.logger.error('simple forms api - manual additions error', { error: e.message })
        pdf_path
      end
    end

    def track_user_identity(confirmation_number)
      identity = data['elect_termination'].presence ? 'terminating' : 'applying'
      StatsD.increment("#{STATS_KEY}.#{identity}")
      Rails.logger.info('Simple forms api - 10-8678 submission user identity', identity:, confirmation_number:)
    end

    private

    def draw_impacted_location_marks(canvas, coordinates, impacted_locations)
      return if impacted_locations.blank?

      has_upper_selection = impacted_locations[:upper_left] || impacted_locations[:upper_right]
      has_lower_selection = impacted_locations[:lower_left] || impacted_locations[:lower_right]

      draw_an_x(canvas, coordinates[:upper_checkbox]) if has_upper_selection
      draw_an_x(canvas, coordinates[:upper_left_radio]) if impacted_locations[:upper_left]
      draw_an_x(canvas, coordinates[:upper_right_radio]) if impacted_locations[:upper_right]

      draw_an_x(canvas, coordinates[:lower_checkbox]) if has_lower_selection
      draw_an_x(canvas, coordinates[:lower_left_radio]) if impacted_locations[:lower_left]
      draw_an_x(canvas, coordinates[:lower_right_radio]) if impacted_locations[:lower_right]
    end

    def check_box_coordinates
      CHECK_BOX_COORDINATES
    end

    def draw_an_x(canvas, coordinates)
      canvas.fill_color(0, 0, 0)
      canvas.font('Helvetica', size: 8, variant: :bold)
      canvas.text('x', at: coordinates)
    end

    def extract_button_list(hash)
      data_hash = {
        upper_left: false,
        upper_right: false,
        lower_left: false,
        lower_right: false
      }
      return data_hash if hash.blank?

      data_hash.keys.each do |location|
        data_hash[location] = hash[location.to_s] == true
      end

      data_hash
    end
  end
end
