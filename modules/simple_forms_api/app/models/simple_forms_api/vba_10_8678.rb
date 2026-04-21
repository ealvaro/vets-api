# frozen_string_literal: true

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
      data['email'].presence || data['email_address'] || data['emailAddress']
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

      # {
      #   deviceOrMedication: 'Hearing Aid',
      #   serviceConnectedDisability: 'Hearing Loss',
      #   impactedLocations: {
      #     upperLeft: true,
      #     upperRight: false,
      #     lowerLeft: false,
      #     lowerRight: false
      #   },
      #   issuingFacility: 'Clarksburg PA Medical Center'
      # }
      appliances.map do |app|
        {
          device: app['deviceOrMedication'],
          disability: app['serviceConnectedDisability'],
          upper_or_lower: extract_button_list(app['impactedLocations'])
        }
      end
    end

    def desired_stamps
      coords = [[0, 0]]
      signature_text = '.'

      [{ coords:, text: signature_text, page: 0 }]
    end

    def submission_date_stamps(time_stamp)
      [
        {
          coords: [460, 690],
          text: "Application Submitted: #{time_stamp}",
          page: 0,
          font_size: 12
        }
      ]
    end

    ##
    #
    def data_massage(num_or_off)
      # Body Massage!
      num_or_off == 'off' ? '"off"' : num_or_off.to_i
    end

    private

    def extract_button_list(hash)
      data_hash = { upper: 'off', upper_side: 'off', lower: 'off', lower_side: 'off' }
      if hash['upperLeft']
        data_hash[:upper] = '1'
        data_hash[:upper_side] = 'LEFT'
      elsif hash['upperRight']
        data_hash[:upper] = '1'
        data_hash[:upper_side] = 'RIGHT'
      end

      if hash['lowerLeft']
        data_hash[:lower] = '2'
        data_hash[:lower_side] = 'LEFT'
      elsif hash['lowerRight']
        data_hash[:lower] = '2'
        data_hash[:lower_side] = 'RIGHT'
      end
      data_hash
    end
  end
end
