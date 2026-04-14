# frozen_string_literal: true

module RequestContextExtension
  def device_id  = get_header(RequestContextMiddleware::DEVICE_ENV_KEY)
  def visit_id   = get_header(RequestContextMiddleware::VISIT_ENV_KEY)
end

ActiveSupport.on_load(:action_dispatch_request) { include RequestContextExtension }

class RequestContextMiddleware
  DEVICE_COOKIE   = 'did'
  VISIT_COOKIE    = 'vid'
  DEVICE_HEADER   = 'X-Device-Id'
  VISIT_HEADER    = 'X-Visit-Id'
  DEVICE_ENV_KEY  = 'action_dispatch.device_id'
  VISIT_ENV_KEY   = 'action_dispatch.visit_id'
  DEVICE_TTL      = 20.years
  VISIT_TTL       = 30.minutes

  def initialize(app, signing_key:, rotated_signing_keys: [])
    @app = app
    @signing_key = signing_key
    @rotated_signing_keys = Array(rotated_signing_keys)
  end

  def call(env)
    req = ActionDispatch::Request.new(env)

    device_id = resolve_id(req, header: DEVICE_HEADER, cookie: DEVICE_COOKIE)
    visit_id  = resolve_id(req, header: VISIT_HEADER,  cookie: VISIT_COOKIE)

    env[DEVICE_ENV_KEY] = device_id
    env[VISIT_ENV_KEY]  = visit_id

    status, headers, body = @app.call(env)

    write_device_response(headers, req, device_id)
    write_visit_response(headers, req, visit_id)

    [status, headers, body]
  end

  private

  def resolve_id(req, header:, cookie:)
    verify_signed(req.cookies[cookie]) || verify_signed(read_header(req, header)) || SecureRandom.uuid
  end

  def write_device_response(headers, req, device_id)
    signed_value = sign(device_id)
    cookie_options = cookie_options_for(signed_value:, secure: req.ssl?, expires: DEVICE_TTL.from_now)

    write_response(headers, header_name: DEVICE_HEADER,
                            cookie_name: DEVICE_COOKIE,
                            signed_value:,
                            cookie_options:)
  end

  def write_visit_response(headers, req, visit_id)
    signed_value = sign(visit_id)
    cookie_options = cookie_options_for(signed_value:, secure: req.ssl?, expires: VISIT_TTL.from_now)

    write_response(headers, header_name: VISIT_HEADER,
                            cookie_name: VISIT_COOKIE,
                            signed_value:,
                            cookie_options:)
  end

  def write_response(headers, header_name:, cookie_name:, signed_value:, cookie_options:)
    headers[header_name] ||= signed_value
    Rack::Utils.set_cookie_header!(headers, cookie_name, cookie_options)
  end

  def cookie_options_for(signed_value:, secure:, expires:)
    {
      value: signed_value,
      path: '/',
      same_site: :lax,
      secure:,
      http_only: true,
      expires:
    }
  end

  def read_header(req, name)
    req.headers[name].presence
  end

  def verifier
    @verifier ||= build_verifier(@signing_key).tap do |v|
      @rotated_signing_keys.each { |old_key| v.rotate(old_key, digest: 'SHA256') }
    end
  end

  def build_verifier(key)
    ActiveSupport::MessageVerifier.new(key, digest: 'SHA256')
  end

  def sign(value)
    verifier.generate(value)
  end

  def verify_signed(signed_value)
    return nil if signed_value.blank?

    verifier.verified(signed_value)
  end
end
