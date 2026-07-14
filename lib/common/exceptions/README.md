## Common::Exceptions

This directory contains the full exception hierarchy used across vets-api. All exceptions are designed to be serializable as JSONAPI-compliant error responses.

## Purpose

To provide a consistent, structured set of exception classes that can be raised anywhere in the application and reliably rendered as well-formed error responses. Each exception maps to an i18n key in `config/locales/exceptions.en.yml`, which controls the title, detail, HTTP status code, and whether the error gets reported to the error tracking backend.

## Class Hierarchy

### Base Classes

**`BaseError`** — the root class all exceptions inherit from. Defines the interface (`errors`, `status_code`, `message`) and i18n lookup conventions. Subclasses must implement `errors`. Also exposes `reportable?` (controls whether the exception is reported to the error tracking backend).

**`SerializableError`** — a plain Ruby object (not an exception itself) that wraps error attributes into a JSONAPI-compatible structure. Fields include `title`, `detail`, `code`, `status`, `source`, `links`, and `meta`. Used internally by exception classes when building their `errors` array.

**`BackendServiceException`** — raised by middleware when a backend service returns an error response. Accepts an i18n key (e.g. `RX139`, `EVSS144`) to look up the appropriate response shape. Falls back to `VA900` for unmapped errors. Stores the original status and body from the upstream response for debugging.

### 4xx Client Errors

| Class | HTTP Status | Description |
|-------|-------------|-------------|
| `AmbiguousRequest` | 400 | Request cannot be disambiguated |
| `BadRequest` | 400 | Generic bad request |
| `FilterNotAllowed` | 400 | A filter parameter is not permitted for this resource |
| `InvalidField` | 400 | A field name in the request is not recognized |
| `InvalidFieldValue` | 400 | A field value in the request is invalid |
| `InvalidFiltersSyntax` | 400 | Filter parameter syntax is malformed |
| `InvalidPaginationParams` | 400 | Pagination parameters are out of range or invalid |
| `InvalidResource` | 400 | The requested resource type is not valid |
| `InvalidSortCriteria` | 400 | Sort parameter refers to a non-sortable field |
| `MaxArraySizeExceeded` | 400 | An array parameter exceeds the allowed size |
| `NoQueryParamsAllowed` | 400 | Query parameters were provided but are not allowed |
| `ParameterMissing` | 400 | A required parameter is absent |
| `ParametersMissing` | 400 | Multiple required parameters are absent |
| `ValidationErrors` | 422 | Model validation failed; wraps ActiveModel errors |
| `ValidationErrorsBadRequest` | 400 | Validation failure rendered as 400 instead of 422 |
| `DetailedSchemaErrors` | 422 | Schema validation failure with field-level detail |
| `SchemaValidationErrors` | 422 | JSON schema validation failure |
| `UnprocessableEntity` | 422 | Generic unprocessable entity |
| `UpstreamUnprocessableEntity` | 422 | Upstream service returned 422 |
| `Unauthorized` | 401 | Authentication required |
| `TokenValidationError` | 401 | Token is invalid or expired |
| `MessageAuthenticityError` | 403 | CSRF or message authenticity check failed |
| `Forbidden` | 403 | Authenticated but not authorized |
| `UnexpectedForbidden` | 403 | Forbidden response was not expected in this context |
| `RecordNotFound` | 404 | A specific record could not be found |
| `ResourceNotFound` | 404 | A resource type or endpoint could not be found |
| `RoutingError` | 404 | No route matched the request |
| `PayloadTooLarge` | 413 | Request body exceeds the allowed size |
| `TooManyRequests` | 429 | Rate limit exceeded |
| `FailedDependency` | 424 | A required dependency failed |

### 5xx Server and Service Errors

| Class | HTTP Status | Description |
|-------|-------------|-------------|
| `InternalServerError` | 500 | Generic server error |
| `NotImplemented` | 501 | Endpoint or feature is not yet implemented |
| `BadGateway` | 502 | Upstream service returned an unexpected response |
| `ServiceUnavailable` | 503 | Upstream service is not available |
| `ServiceOutage` | 503 | A known service outage is in effect |
| `GatewayTimeout` | 504 | Upstream service did not respond in time |
| `Timeout` | 500 | Generic timeout |
| `ClientDisconnected` | 499 | Client disconnected before the response was sent |
| `ExternalServerInternalServerError` | 500 | An external service returned a 500 |
| `OpenIdServiceError` | `%{status}` | OpenID Connect service error with caller-supplied HTTP status |
| `ServiceError` | 500 | Generic service-level error from a backend integration |
| `UpstreamPartialFailure` | 502 | Upstream returned partial data; used to signal degraded responses |
| `PrescriptionRefillResponseMismatch` | 502 | Prescription service response did not match expected shape |

## Usage

Raise exceptions directly, or via middleware. Each class has a unique initializer — check the individual file for accepted arguments.

```ruby
raise Common::Exceptions::RecordNotFound, @prescription.id
raise Common::Exceptions::UnprocessableEntity.new(detail: 'Password is incorrect', source: 'MyService')
raise Common::Exceptions::BackendServiceException.new('RX139', { detail: message }, status, body)
```

To customize the message, detail, or error reporting behavior for any exception, add or update its key in `config/locales/exceptions.en.yml`.
