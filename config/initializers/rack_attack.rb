# frozen_string_literal: true

class Rack::Attack
  # we're behind a load balancer and/or proxy, which is what request.ip returns
  class Request < ::Rack::Request
    def remote_ip
      # HTTP_X_REAL_IP is the real one: our revproxy sets `X-Real-IP`, and Rack/Puma
      # normalizes incoming headers to `HTTP_` + upcased + underscored env keys, so
      # that's the only way this header actually shows up on a real request. It's only
      # trustworthy when it comes from a proxy we've configured Rails to trust -- otherwise
      # a direct caller could set it themselves to rotate their throttle bucket.
      # `X-Real-Ip` (no HTTP_ prefix) never gets set by an actual request, but is kept here
      # because spec/middleware/rack/attack_spec.rb injects it as a literal env key via
      # Rack::Test rather than a real header, so it needs to be checked too.
      @remote_ip ||= (trusted_x_real_ip || env['X-Real-Ip'] || ip).to_s
    end

    private

    def trusted_x_real_ip
      return nil unless env['HTTP_X_REAL_IP']

      trusted_proxies = Array(Rails.application.config.action_dispatch.trusted_proxies)
      case env['REMOTE_ADDR']
      when *trusted_proxies
        env['HTTP_X_REAL_IP']
      end
    end
  end

  Rack::Attack.cache.store = Rack::Attack::StoreProxy::RedisStoreProxy.new($redis)

  throttle('example/ip', limit: 1, period: 5.minutes) do |req|
    req.ip if req.path == '/v0/limited'
  end

  # Rate-limit facilities_va/v2/va lookup -- part of locator.
  # See https://dsva.slack.com/archives/C0FQSS30V/p1695046907329529
  # No systemic failure, but potential "DoS" caused a spike in traffic from one IP.
  throttle('facilities_api/v2/va/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path == '/facilities_api/v2/va'
  end

  # Rate-limit PPMS lookup, in order to bore abusers.
  # See https://va.ghe.com/software/va.gov-team-sensitive/blob/master/Postmortems/2021-08-16-facility-locator-possible-DOS.md
  # for details. Covers all ccp sub-routes (index, provider, pharmacy, urgent_care, specialties).
  throttle('facilities_api/v2/ccp/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/facilities_api/v2/ccp')
  end

  throttle('vic_profile_photos_download/ip', limit: 8, period: 5.minutes) do |req|
    req.remote_ip if req.path == '/v0/vic/profile_photo_attachments' && req.get?
  end

  throttle('vic_profile_photos_upload/ip', limit: 8, period: 5.minutes) do |req|
    req.remote_ip if req.path == '/v0/vic/profile_photo_attachments' && req.post?
  end

  throttle('vic_supporting_docs_upload/ip', limit: 8, period: 5.minutes) do |req|
    req.remote_ip if req.path == '/v0/vic/supporting_documentation_attachments' && req.post?
  end

  throttle('vic_submissions/ip', limit: 10, period: 1.minute) do |req|
    req.remote_ip if req.path == '/v0/vic/vic_submissions' && req.post?
  end

  throttle('check_in/ip', limit: 10, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/check_in') && !Settings.vsp_environment.match?(/local|development|staging/)
  end

  throttle('medical_copays/ip', limit: 20, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/medical_copays') && req.get?
  end

  throttle('education_benefits_claims/v0/ip', limit: 15, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/education_benefits_claims') && req.post?
  end

  throttle('form214192/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/form214192') && req.post?
  end

  throttle('form21p530a/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/form21p530a') && req.post?
  end

  throttle('form210779/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/form210779') && req.post?
  end

  throttle('form212680/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/v0/form212680') && req.post?
  end

  # VAOS Request Limits
  throttle('appointments/post', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/appointments') && req.post?
  end

  throttle('appointments/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/appointments') && req.get?
  end

  throttle('appointments/put', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/appointments') && req.put?
  end

  throttle('providers/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/providers') && req.get?
  end

  throttle('clinics/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/locations') && req.get?
  end

  throttle('cc_eligibility/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/community_care/eligibility') && req.get?
  end

  throttle('patients/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/eligibility') && req.get?
  end

  throttle('scheduling_configurations/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/scheduling/configurations') && req.get?
  end

  throttle('facilities/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/facilities') && req.get?
  end

  throttle('relationships/get', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path.starts_with?('/vaos/v2/relationships') && req.get?
  end

  throttle('ask_va_api/zip_state_validation', limit: 60, period: 1.minute) do |req|
    req.remote_ip if req.path == '/ask_va_api/v0/zip_state_validation' &&
                     req.post? &&
                     Settings.vsp_environment.eql?('production')
  end

  throttle('ask_va_api/diagnostics', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path == '/ask_va_api/v0/diagnostics' && req.get?
  end

  # Rate-limit the unauthenticated next_steps_email endpoint.
  # This endpoint sends VA-branded emails via VA Notify. Without throttling it
  # is an open relay. 5 req/min per IP is generous for a "just completed a form" flow.
  throttle('representation_management/next_steps_email/ip', limit: 5, period: 1.minute) do |req|
    req.remote_ip if req.path == '/representation_management/v0/next_steps_email' && req.post?
  end

  # Per-destination throttle prevents flooding a single recipient from distributed IPs.
  # Handles both camelCase (vets-website) and snake_case request bodies.
  throttle('representation_management/next_steps_email/email', limit: 3, period: 1.hour) do |req|
    if req.path == '/representation_management/v0/next_steps_email' && req.post?
      begin
        body = req.body&.read(2048).to_s
        req.body&.rewind
        parsed = JSON.parse(body)
        email = parsed.dig('nextStepsEmail', 'emailAddress') ||
                parsed.dig('next_steps_email', 'email_address')
        email ? Digest::SHA256.hexdigest(email.downcase.strip) : req.remote_ip
      rescue JSON::ParserError, IOError, NoMethodError
        req.remote_ip
      end
    end
  end

  # Always allow requests from below IP addresses for load testing
  # `100.103.248.0 - 100.103.248.255`
  # `100.103.251.128 - 100.103.251.255`
  # `10.247.104.` - tevi-dev-load-testing host IPs
  # (blocklist & throttles are skipped)
  Rack::Attack.safelist('allow requests from loadtest host') do |req|
    # Requests are allowed if the return value is truthy
    req.ip.match?(/100.103.248.(\b[0-9]\b|\b[1-9][0-9]\b|1[0-9]{2}|2[0-4][0-9]|25[0-5])
                  |100.103.251.(12[8-9]|1[3-9]\d|2[0-4]\d|25[0-5])
                  |10.247./)
  end

  # Source: https://github.com/kickstarter/rack-attack#x-ratelimit-headers-for-well-behaved-clients
  Rack::Attack.throttled_responder = lambda do |request|
    rate_limit = request.env['rack.attack.match_data']

    now = Time.zone.now
    headers = {
      'X-RateLimit-Limit' => rate_limit[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + (rate_limit[:period] - (now.to_i % rate_limit[:period]))).to_i
    }

    [429, headers, ['throttled']]
  end
end
