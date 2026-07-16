# VASS Module

## Overview

The VASS (Veterans Affairs Scheduling System) module enables non-authenticated, first-time users to schedule appointments with the VA, including suicide awareness and health appointments.

## Features

- **One-Time Password (OTP) Authentication**: Secure verification for non-authenticated users
- **VANotify Integration**: OTP delivery via email
- **VASS API Integration**: External service integration for appointment scheduling
- **Redis Storage**: Session and OTP management, OAuth token caching
- **RESTful API**: JSON API endpoints following vets-api patterns
- **Service Layer**: Business logic abstraction over HTTP client
- **Circuit Breaker**: Fault tolerance for external API calls

## Architecture

This module follows the Rails Engine pattern used throughout vets-api. It provides:

- Isolated namespace (`Vass`)
- API-only configuration
- Integration with existing vets-api infrastructure (Redis, VANotify, StatsD)
- Forward proxy support for external VASS API calls
- Layered architecture: Controllers → Services → Client → External API

### Architecture Layers

```
┌─────────────────────────────────────────┐
│  Service Layer                          │
│  - Vass::AppointmentsService            │
│    (Business logic, error handling)     │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  HTTP Client                            │
│  - Vass::Client                         │
│    (OAuth, monitoring, requests)        │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  External VASS API                      │
│  (Microsoft Azure hosted)               │
└─────────────────────────────────────────┘
```

## API Endpoints

### v0 API

#### Session Management

- `POST /vass/v0/request-otp` - Create session and send OTP
- `POST /vass/v0/authenticate-otp` - Validate OTP
- `POST /vass/v0/revoke-token` - Revoke JWT token (logout)

#### Appointment Management (existing endpoints)

- `GET /vass/v0/appointments` - List available appointment slots
- `POST /vass/v0/appointments` - Book an appointment
- `GET /vass/v0/appointments/:id` - Get appointment details

## Development

### Running Tests

```bash
cd modules/vass
bundle exec rspec
```

### Service Layer Usage

The `Vass::AppointmentsService` provides a clean interface for VASS operations:

```ruby
# Initialize service with veteran EDIPI
service = Vass::AppointmentsService.build(
  edipi: '1234567890',
  correlation_id: 'optional-correlation-id'
)

# Check appointment availability
availability = service.get_availability(
  start_date: Time.zone.now,
  end_date: Time.zone.now + 7.days,
  veteran_id: 'vet-123'
)

# Create an appointment
appointment = service.save_appointment(
  appointment_params: {
    veteran_id: 'vet-123',
    time_start_utc: Time.zone.now + 1.day,
    time_end_utc: Time.zone.now + 1.day + 30.minutes,
    selected_agent_skills: ['skill-1', 'skill-2']
  }
)

# Get veteran's appointments
appointments = service.get_appointments(veteran_id: 'vet-123')

# Cancel an appointment
service.cancel_appointment(appointment_id: 'appt-123')

# Get veteran information
veteran = service.get_veteran_info(veteran_id: 'vet-123')

# List available agent skills
skills = service.get_agent_skills
```

### Local Configuration

The module requires the following settings in `config/settings.yml`:

```yaml
vass:
  auth_url: "https://login.microsoftonline.com"
  tenant_id: "your-tenant-id"
  client_id: "your-client-id"
  client_secret: "your-client-secret"
  scope: "https://api.va.gov/.default"
  api_url: "https://vass-api.va.gov"
  subscription_key: "your-subscription-key"
  service_name: "vass_api"
  timeout: 30
  forward_proxy_url: "your-proxy-url"
  mock: false
```

### Testing

To test the service layer:

```bash
cd modules/vass
bundle exec rspec spec/services/vass/appointments_service_spec.rb

## Documentation

- [OpenAPI/Swagger Documentation](/vass/v0/apidocs)
- [Implementation Tickets](../../vass_implementation_tickets.md)

## Dependencies

- **Redis**: For OAuth token caching, OTP and session storage
- **VANotify**: For OTP delivery
- **VASS API**: External appointment scheduling service (Microsoft Azure)
- **Circuit Breaker**: Breakers gem for fault tolerance
- **VCR**: For HTTP interaction testing

## Error Handling

### Non-Standard Error Responses

**IMPORTANT**: The VASS API uses a non-standard error handling pattern. Most endpoints return **HTTP 200 for both successful and error responses**. Errors are indicated by a `"success": false` field in the JSON response body rather than proper HTTP status codes.

#### Error Response Format

```json
{
  "success": false,
  "message": "Provided veteranId does not have a valid GUID format",
  "data": null,
  "correlationId": "req123",
  "timeStamp": "2025-12-02T12:00:00Z"
}
```

Success responses have `"success": true`:

```json
{
  "success": true,
  "message": null,
  "data": { "appointmentId": "abc-123" },
  "correlationId": "req123",
  "timeStamp": "2025-12-02T12:00:00Z"
}
```

#### Affected Endpoints

The following endpoints return HTTP 200 for errors:

- `AppointmentAvailability`
- `CancelAppointment`
- `GetVeteran`
- `GetVeteranAppointment`
- `GetVeteranAppointments`
- `SaveAppointment`

**Exception**: `GetAgentSkills` returns proper HTTP 400 for authentication errors.

#### Custom Middleware

To handle this non-standard behavior, the module uses `Vass::ResponseMiddleware` (similar to `EVSS::ErrorMiddleware`). This Faraday middleware:

1. Intercepts HTTP 200 responses with JSON content
2. Checks the `success` field in the response body
3. When `success == false`, raises a `Common::Exceptions::BackendServiceException`
4. Maps error messages to appropriate HTTP status codes:
   - "Missing Parameters" → 400 (Bad Request)
   - "Invalid GUID format" → 422 (Unprocessable Entity)
   - "not found" → 404 (Not Found)
   - "not available" → 422 (Unprocessable Entity)
   - "invalid date" → 422 (Unprocessable Entity)
   - Unknown errors → 502 (Bad Gateway)

This allows the existing error handlers to work correctly despite the non-standard API behavior.

### Service Layer Error Types

The service layer provides comprehensive error handling:

- `Vass::Errors::AuthenticationError` - OAuth/authentication failures (401)
- `Vass::Errors::NotFoundError` - Resource not found (404)
- `Vass::Errors::ValidationError` - Request validation failures
- `Vass::Errors::VassApiError` - VASS API errors (5xx)
- `Vass::Errors::ServiceError` - General service errors
- `Vass::Errors::RedisError` - Redis connection/storage issues

All errors are logged without PHI and rendered in JSON:API format.

## Monitoring

All endpoints and service calls are instrumented with StatsD. Traces/logs group under the Datadog APM service name `vass` (`service_tag 'vass'` on `Vass::ApplicationController`).

Naming convention: `api.vass.{layer}.{component}.{action}.{outcome}`  
See `lib/vass/metrics_constants.rb` and `app/controllers/concerns/vass/metrics_tracking.rb`.

### Why some events appear on two metrics

Controller metrics answer “did this HTTP endpoint succeed or fail?”  
Infrastructure metrics answer “which product/auth outcome was it?” (expired OTP, rate limit, identity mismatch, no slots, etc.).

For several user-error paths we emit both on purpose — for example an expired OTP increments:

1. `api.vass.infrastructure.session.otp.expired` (breakdown by outcome)
2. `api.vass.controller.sessions.authenticate_otp.failure` (endpoint failure rate)

Same pattern for invalid OTP, OTP generation/validation rate limits, and identity validation failures. **Do not add those two series together** when counting unique user errors — pick controller for endpoint health, or infrastructure for outcome mix.

Availability soft outcomes (no cohorts / next cohort / already booked / no slots) are **infrastructure-only**. Use `appointments.availability.total` as the request denominator.

Upstream `success: false` responses can also show up as `http_200_errors` + client `.fail` + controller `.failure` (different layers). Treat them as layered signals, not a single summed error total.

### Controller metrics

Pattern: `api.vass.controller.{sessions|appointments}.{action}.{success|failure|total}`

Tags: `service:vass`, `endpoint`, `http_method`, optional `http_status`, `error_type` on failures.

| Metric base | When |
|-------------|------|
| `…sessions.request_otp` | Send OTP |
| `…sessions.authenticate_otp` | Verify OTP / issue JWT (`.failure` includes expired OTP and metadata_not_found) |
| `…sessions.revoke_token` | Logout |
| `…appointments.availability` | Slot fetch — also emits `.total` on every attempt |
| `…appointments.create` / `.show` / `.cancel` / `.topics` | Book / details / cancel / topics |

Availability `.success` fires only for `:available_slots`. Soft outcomes do not increment `.failure`.

### Infrastructure metrics

Pattern: `api.vass.infrastructure.*`  
Tags: `service:vass` (plus `attempt:` / `reason:` where noted).

| Metric | When |
|--------|------|
| `…rate_limit.generation.exceeded` | OTP send rate limited |
| `…rate_limit.validation.exceeded` | OTP validate rate limited |
| `…session.otp.expired` / `.invalid` | Expired / wrong OTP (`attempt:N` on invalid) |
| `…session.jwt.expired` / `.missing` / `.invalid` / `.revoked` | JWT auth failures (`reason:` tag) |
| `…auth.identity_validation.failure` | Last name/DOB mismatch |
| `…auth.missing_edipi` | Session has no EDIPI after JWT auth |
| `…availability.no_cohorts` | Outside all cohorts |
| `…availability.next_cohort` | Booking window not open yet |
| `…availability.already_booked` | Veteran already booked |
| `…availability.no_slots_available` | In window, zero bookable slots |

### Client / middleware metrics

Upstream VASS HTTP calls use `Common::Client::Concerns::Monitoring` (`STATSD_KEY_PREFIX = 'api.vass'`):

- `api.vass.oauth_token_request.total` / `.fail`
- `api.vass.get_appointment_availability.total` / `.fail`
- `api.vass.save_appointment.total` / `.fail`
- `api.vass.cancel_appointment.total` / `.fail`
- `api.vass.get_veteran_appointment.total` / `.fail`
- `api.vass.get_veteran_appointments.total` / `.fail`
- `api.vass.get_veteran.total` / `.fail`
- `api.vass.get_agent_skills.total` / `.fail`

Client failure tags use platform conventions: `error:ErrorClassName`, optional `status:HTTPStatus` (these do not include `service:vass`).

HTTP 200 responses with JSON `success: false` also increment `api.vass.http_200_errors` (tag `error_status`) via `Vass::ResponseMiddleware`.

Outgoing call **latency** is covered by Datadog APM on the `vass` service (not a custom `StatsD.measure`).

## Support

For questions or issues, contact the VASS team.
