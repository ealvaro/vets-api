# frozen_string_literal: true

module ErrorHandling
  extend ActiveSupport::Concern

  KNOWN_BTSSS_STATUSES = [400, 401, 403, 404, 409, 413, 422, 429, 500, 502, 503, 504].freeze

  included do
    rescue_from Common::Exceptions::BackendServiceException, with: :render_error
    rescue_from Faraday::Error, with: :render_error
    rescue_from ArgumentError, with: :render_error
    rescue_from Common::Exceptions::BadRequest, with: :render_error
    rescue_from Common::Exceptions::UnprocessableEntity, with: :render_error
    rescue_from Common::Exceptions::ResourceNotFound, with: :render_error
  end

  private

  def render_error(e)
    raise unless unified_error_handling_enabled?

    exception = normalize_exception(e)
    log_exception(e, exception)
    render json: { errors: exception.errors }, status: exception.status_code
  end

  def unified_error_handling_enabled?
    Flipper.enabled?(:travel_pay_unified_error_handling, current_user)
  end

  def log_exception(original, exception)
    level = exception.is_a?(Common::Exceptions::BackendServiceException) ? :error : :warn

    Rails.logger.public_send(
      level,
      "#{human_readable_message}: #{original.class} - #{original.message}",
      code: exception.respond_to?(:key) ? exception.key : nil,
      status: exception.status_code
    )
  end

  def normalize_exception(e)
    case e
    when Common::Exceptions::BackendServiceException,
         Common::Exceptions::BadRequest,
         Common::Exceptions::UnprocessableEntity,
         Common::Exceptions::ResourceNotFound
      e
    when Faraday::ResourceNotFound
      Common::Exceptions::BackendServiceException.new('BTSSS-API_404', { status: 404 }, 404)
    when Faraday::TimeoutError
      Common::Exceptions::BackendServiceException.new('BTSSS-API_CONNECTION_TIMEOUT', { status: 504 }, 504)
    when Faraday::Error
      normalize_faraday_error(e)
    when ArgumentError
      Common::Exceptions::BadRequest.new(detail: e.message)
    else
      Common::Exceptions::BackendServiceException.new('BTSSS-API_500', { status: 500 }, 500)
    end
  end

  def normalize_faraday_error(e)
    upstream_status = e.response&.dig(:status)
    if upstream_status && KNOWN_BTSSS_STATUSES.include?(upstream_status)
      Common::Exceptions::BackendServiceException.new("BTSSS-API_#{upstream_status}",
                                                      { status: upstream_status }, upstream_status)
    else
      Common::Exceptions::BackendServiceException.new('BTSSS-API_CONNECTION_FAILED', { status: 503 }, 503)
    end
  end

  ##
  # Derives a human-readable operation message from the controller and action name.
  # Looks up i18n key at travel_pay.errors.<controller>.<action>_failed,
  # falls back to a generated message if no key is defined.
  #
  def human_readable_message
    controller = controller_path.split('/').last
    I18n.t("travel_pay.errors.#{controller}.#{action_name}_failed", default: nil) ||
      "TravelPay #{controller}##{action_name} failed"
  end
end
