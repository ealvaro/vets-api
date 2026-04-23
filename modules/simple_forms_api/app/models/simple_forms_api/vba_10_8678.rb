# frozen_string_literal: true

require 'hexapdf'
require 'simple_forms_api/overflow_108678'

module SimpleFormsApi
  class VBA108678 < BaseForm
    STATS_KEY = 'api.simple_forms_api.10_8678'
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
      data.dig('fullName', 'first') || ''
    end

    def middle_initial
      data.dig('fullName', 'middle') || ''
    end

    def last_name
      data.dig('fullName', 'last') || ''
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
      data['email'].presence || data['email_address'].presence || data['emailAddress'].presence
    end

    # Signature
    def signature
      data['statementOfTruthSignature'] || data['veteranSignature']
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
        'source' => 'VA Platform Digital Forms',
        'docType' => data['form_number'],
        'businessLine' => 'CMP'
      }
    end

    # Format appliances for PDF
    def map_appliances
      return [] if appliances.empty?

      appliances.map do |app|
        {
          device: app['deviceOrMedication'],
          disability: app['serviceConnectedDisability'],
          upper_or_lower: extract_button_list(app['impactedLocations'])
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

      devices_list = gather_overflow_devices(data['appliances'])
      return nil if devices_list.blank?

      Overflow108678.new(devices_list, cutoff: 1).generate
    end

    # Due to a bug in the PDF we cannot select the Upper or Lower checkboxes,
    # this method manually writes a "X" to the pdf in the correct spots.
    # rubocop:disable Metrics/MethodLength
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

            draw_an_x(canvas, coords[idx][:upper]) if item[:upper_or_lower][:upper] != 'Off'
            draw_an_x(canvas, coords[idx][:lower]) if item[:upper_or_lower][:lower] != 'Off'
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
    # rubocop:enable Metrics/MethodLength

    def gather_overflow_devices(appliances)
      apps = []
      appliances.each do |app|
        impact_area = app['impactedLocations'] ||= {}
        upper_device = impact_area['upperLeft'] == true && impact_area['upperRight'] == true
        lower_device = impact_area['lowerLeft'] == true && impact_area['lowerRight'] == true
        if upper_device && lower_device
          apps << app.merge({ 'both' => true })
        elsif upper_device || lower_device
          apps << app
        end
      end
      apps
    end

    private

    def check_box_coordinates
      [
        { upper: [313.5, 460], lower: [451.5, 459.5] },
        { upper: [314, 424], lower: [451.5, 423.5] },
        { upper: [314, 388], lower: [451.5, 387.5] },
        { upper: [314, 351.5], lower: [451.5, 351] }
      ]
    end

    def draw_an_x(canvas, coordinates)
      canvas.fill_color(0, 0, 0)
      canvas.font('Helvetica', size: 8, variant: :bold)
      canvas.text('x', at: coordinates)
    end

    def extract_button_list(hash)
      data_hash = { upper: 'Off', upper_side: 'Off', lower: 'Off', lower_side: 'Off' }
      return data_hash if hash.blank?

      if hash['upperLeft']
        data_hash[:upper] = 1
        data_hash[:upper_side] = 'LEFT'
      elsif hash['upperRight']
        data_hash[:upper] = 1
        data_hash[:upper_side] = 'RIGHT'
      end

      if hash['lowerLeft']
        data_hash[:lower] = 2
        data_hash[:lower_side] = 'LEFT'
      elsif hash['lowerRight']
        data_hash[:lower] = 2
        data_hash[:lower_side] = 'RIGHT'
      end
      data_hash
    end
  end
end
