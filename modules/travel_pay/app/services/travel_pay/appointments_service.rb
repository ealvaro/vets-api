# frozen_string_literal: true

module TravelPay
  class AppointmentsService
    include Monitorable

    def initialize(auth_manager)
      @auth_manager = auth_manager
    end

    ##
    # gets all appointments and finds the singular BTSSS appointment that matches the provided datetime
    # @params: datetime string ('2024-01-01T12:45:34.465Z')
    #
    # @return {
    # 'id' => 'string',
    # 'appointmentSource' => 'string',
    # 'appointmentDateTime' => 'string',
    # 'appointmentName' => 'string',
    # 'appointmentType' => 'string',
    # 'facilityName' => 'string',
    # 'serviceConnectedDisability' => int,
    # 'currentStatus' => 'string',
    # 'appointmentStatus' => 'string',
    # 'externalAppointmentId' => 'string',
    # 'associatedClaimId' => string,
    # 'associatedClaimNumber' => string,
    # 'isCompleted' => boolean,
    # }
    #
    #
    def get_appointment_by_date_time(params = {})
      auth_session = @auth_manager.authorize
      faraday_response = client.get_all_appointments(auth_session, { 'excludeWithClaims' => true })
      raw_appointments = faraday_response.body['data'].deep_dup
      appointment = find_by_date_time(params['appt_datetime'], raw_appointments)

      {
        data: appointment
      }
    end

    ##
    # gets an appointment for the provided datetime if it exists,
    # TP API will create it if not
    # @params:
    #  {
    #   appointment_date_time: datetime string ('2024-01-01T12:45:34.465Z'),
    #   facility_station_number: string (i.e. facilityId),
    #   appointment_name: string, **Optional - but will fail if passed an empty string
    #   appointment_type: string, 'CompensationAndPensionExamination' || 'Other'
    #   is_complete: boolean,
    #  }
    #
    # @return [TravelPay::Appointment]
    #
    #
    def find_or_create_appointment(params = {})
      if params['appointment_date_time'].nil?
        monitor.log(:error, 'Invalid appointment time provided (appointment time cannot be nil).')
        raise ArgumentError, message: 'Invalid appointment time provided (appointment time cannot be nil).'
      elsif params['appointment_date_time'].present?
        # Ensure the date is valid
        DateUtils.try_parse_date(params['appointment_date_time'])

        appointments = fetch_find_or_create_appointments(params)

        non_cancelled = appointments&.find do |appt|
          !appt['appointmentStatus']&.downcase&.include?('cancel')
        end

        log_find_or_create_result(appointments, non_cancelled, params)

        {
          data: non_cancelled || appointments&.first
        }
      end
    rescue ArgumentError => e
      monitor.log(:error, "#{e} Invalid appointment time provided (given: #{params['appointment_date_time']}).")
      raise ArgumentError, "#{e} Invalid appointment time provided (given: #{params['appointment_date_time']})."
    end

    ##
    # Searches for appointments using a date range and optional filters.
    # Returns the data array from the BTSSS response, or an empty array
    # if no appointments match.
    #
    # @param params [Hash] snake_case search params (see AppointmentsClient#search_appointments)
    # @return [Array] appointment records
    #
    def search_appointments(params = {})
      auth_session = @auth_manager.authorize
      response = client.search_appointments(auth_session, params)
      response.body['data'] || []
    end

    ##
    # Creates a new user-created appointment in BTSSS.
    # Returns the data object from the BTSSS response, which includes the new appointmentId.
    #
    # @param params [Hash] snake_case appointment params (see AppointmentsClient#create_appointment)
    # @return [Hash] appointment data including appointmentId
    #
    def create_appointment(params = {})
      auth_session = @auth_manager.authorize
      response = client.create_appointment(auth_session, params.merge('appointment_type' => 'Care'))
      response.body['data']
    end

    BASE_REQUIRED_FIELDS = %w[appointment_date_time facility_station_number].freeze
    V4_REQUIRED_FIELDS = %w[facility_name].freeze

    def validate_required_params!(params, use_v4_api: false)
      required = use_v4_api ? BASE_REQUIRED_FIELDS + V4_REQUIRED_FIELDS : BASE_REQUIRED_FIELDS

      missing = required.select { |key| params[key].blank? }
      return if missing.empty?

      monitor.track_request(:error, "Missing required params for find-or-add appointments (given: #{missing.map do |k|
        "#{k}=#{params[k].inspect}"
      end.join(', ')}).", 'travel_pay.appointments.find_or_create.missing_params')
      raise Common::Exceptions::BadRequest.new(
        detail: "Missing required params: #{missing.join(', ')}"
      )
    end

    private

    def fetch_find_or_create_appointments(params)
      auth_session = @auth_manager.authorize
      use_v4_api = @auth_manager.user.present? && Flipper.enabled?(:travel_pay_appt_add_v4_upgrade, @auth_manager.user)
      validate_required_params!(params, use_v4_api:)
      faraday_response = client.find_or_create(auth_session, params, use_v4_api:)
      faraday_response.body['data']
    end

    def log_find_or_create_result(appointments, non_cancelled, params)
      log_params = {
        appointment_date_time: params['appointment_date_time'],
        facility_station_number: params['facility_station_number']
      }

      if appointments.blank?
        monitor.log(:warn, 'No appointments returned from find-or-add', **log_params)
      elsif appointments.length > 1
        monitor.log(:info, "Multiple appointments returned from find-or-add (count: #{appointments.length})",
                    **log_params)
        if non_cancelled.nil?
          monitor.log(:warn, "All appointments returned from find-or-add are cancelled (count: #{appointments.length})",
                      **log_params)
        end
      end
    end

    def find_by_date_time(date_string, appointments)
      if date_string.nil?
        monitor.log(:error, 'Invalid appointment time provided (appointment time cannot be nil).')
        raise ArgumentError, message: 'Invalid appointment time provided (appointment time cannot be nil).'
      elsif date_string.present?
        parsed_date_time = DateUtils.strip_timezone(date_string)
        appointments.find do |appt|
          begin
            parsed_appt_time = DateUtils.strip_timezone(appt['appointmentDateTime'])
          rescue TravelPay::InvalidComparableError => e
            monitor.log(:warn, "#{e} Appointment Datetime was nil")
          end
          !appt['appointmentDateTime'].nil? && parsed_date_time.eql?(parsed_appt_time)
        end
      end
    rescue ArgumentError => e
      monitor.log(:error, "#{e} Invalid appointment time provided (given: #{date_string}).")
      raise ArgumentError, "#{e} Invalid appointment time provided (given: #{date_string})."
    end

    def client
      TravelPay::AppointmentsClient.new
    end
  end
end
