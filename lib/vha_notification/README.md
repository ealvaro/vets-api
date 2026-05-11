# VHA Notification Service

This service handles communication with the VHA (Veterans Health Administration) Notification API to automatically notify VHA when a Veteran checks the MST (Military Sexual Trauma) consent box.

## Overview

The VHA Notification Service sends MST consent information to the VHA API when a veteran provides consent through the form. This is part of the MST Consent Automation feature.

## Architecture

- **Service**: `VhaNotification::Service` - Main service for sending consent updates
- **Configuration**: `VhaNotification::Configuration` - Handles API connection setup and consent update requests
- **JWT Generator**: `VhaNotification::JwtGenerator` - VHA-specific wrapper that creates bearer tokens by delegating to `Common::JwtGenerator`
- **Constants**: `VhaNotification::Constants` - error messages, and StatsD metrics

## API Endpoints

### Consent Update Endpoint

```
PUT /api/v1/cfapivhanotificationapi/vha-consent-and-enrollment/{PID}
Authorization: Bearer {token}
```

**Request Parameters:**

- `source` - eg. "ibm"
- `vhaCommsConsent` - true or false
- `participantId` - same as the {PID} passed in the endpoint

## Configuration

`vha_notification` is configured in `config/settings.yml` as:

```yaml
vha_notification:
  base_url: <%= ENV['vha_notification__base_url'] %>
  source: <%= ENV['vha_notification__source'] %>
  station_id: <%= ENV['vha_notification__station_id'] %>
  user_id: <%= ENV['vha_notification__user_id'] %>
  application_id: <%= ENV['vha_notification__application_id'] %>
  issuer: <%= ENV['vha_notification__issuer'] %>
  jwt_secret: <%= ENV['vha_notification__jwt_secret'] %>
  timeout: 30
```

Environment variables must be provisioned for:

- `vha_notification__base_url` - VHA Notification API base URL
- `vha_notification__source` - Source value sent in the consent payload (falls back to `ibm` when blank)
- `vha_notification__station_id` - VHA station identifier (used in JWT claim)
- `vha_notification__user_id` - VHA user identifier (used in JWT claim)
- `vha_notification__issuer` - JWT issuer claim value
- `vha_notification__jwt_secret` - Signing secret used by `VhaNotification::JwtGenerator` (which delegates to `Common::JwtGenerator`)

The bearer token used for the `Authorization` header is generated in service code via `VhaNotification::JwtGenerator.encode_jwt`, which delegates to `Common::JwtGenerator` using the settings above.

## Usage

### Basic Example

```ruby
service = VhaNotification::Service.new
pid = '1234567890'
consent_data = true

result = service.send_mst_consent(pid, consent_data)

if result[:success]
  puts "MST consent successfully sent"
  puts result[:response]
end
```

### Error Handling

The service raises `VhaNotification::ServiceError` on failures:

```ruby
begin
  result = service.send_mst_consent(pid, consent_data)
rescue VhaNotification::ServiceError => e
  Rails.logger.error("Failed to send MST consent: #{e.message}")
end
```

### Payload Sent To VHA

`send_mst_consent(pid, consent_data)` builds and sends this payload:

```json
{
  "source": "ibm",
  "vhaCommsConsent": true,
  "participantId": 1234567890
}
```

Notes:

- `source` defaults to `"ibm"` when `Settings.vha_notification.source` is blank.
- `vhaCommsConsent` must be a boolean (`true` or `false`).
- `participantId` is `pid.to_i`.

## Testing

Run unit tests for the service:

```bash
bundle exec rspec spec/lib/vha_notification/service_spec.rb
```

Run integration/VCR tests:

```bash
bundle exec rspec spec/lib/vha_notification/service_integration_spec.rb
```

Run both specs together:

```bash
bundle exec rspec spec/lib/vha_notification/service_spec.rb spec/lib/vha_notification/service_integration_spec.rb
```

## Instrumentation

### StatsD Metrics

The service records the following metrics:

- `api.vha_notification.get_token.success` - Successful token retrieval
- `api.vha_notification.get_token.fail` - Failed token retrieval
- `api.vha_notification.send_consent.success` - Successful consent update
- `api.vha_notification.send_consent.fail` - Failed consent update
- `api.vha_notification.send_consent.total` - Total consent update attempts

### Logging

All operations are logged to Rails.logger with context including:

- Service name
- HTTP status (for responses)
- Error details (for failures)

**Note:** PII such as participant IDs (PID) is intentionally omitted from logs and error messages to protect veteran privacy.

Example logs:

```
VHA Notification: MST consent successfully sent (status: 200, service: VhaNotification)
VHA Notification: Failed to send MST consent (error: "Connection timeout", error_class: "Faraday::TimeoutError", service: VhaNotification)
VHA Notification: Failed to generate bearer token (error: "Invalid JWT secret", error_class: "VhaNotification::ServiceError")
```

## Error Handling & Resilience

- **Breakers Pattern**: Faraday breakers are configured to prevent cascading failures
- **Timeouts**: Default 30-second timeout (configurable via settings)
- **Validation**: Input validation for PID and consent data
- **Circuit Breaker**: Automatic failure detection and fast-fail when service is unavailable

## Related Issues

- Main Epic: [#136484 MST Consent VHA Notification Automation](https://github.com/department-of-veterans-affairs/va.gov-team/issues/136484)
- Service Implementation: [#139857](https://github.com/department-of-veterans-affairs/va.gov-team/issues/139857)
- Sidekiq Job: [#136486](https://github.com/department-of-veterans-affairs/va.gov-team/issues/136486)
