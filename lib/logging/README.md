# Logging

Centralized logging utilities for vets-api that provide standardized monitoring, error tracking, and metrics collection across all services.

## Overview

The logging library provides a unified interface for:
- **Structured logging** with Rails.logger
- **Metrics collection** with StatsD
- **Error tracking** with consistent formatting
- **PII protection** through parameter filtering

## Components

### Logging::Monitor

Generic monitoring class for tracking service operations with both logging and metrics.

```ruby
# Initialize monitor for your service
monitor = Logging::Monitor.new('my-service')

# Track successful operations
monitor.track_request(:info, 'Operation completed', 'my_service.success')

# Track errors with context
monitor.track_request(:error, 'API call failed', 'my_service.error',
                     exception: error.message,
                     tags: ['endpoint:claims'])
```

### Other Components

- [`Logging::Helper::DataScrubber`](helper/data_scrubber.rb) - PII removal utilities
- [`Logging::ThirdPartyTransaction`](third_party_transaction.rb) - External service call logging
- [`Logging::Include::Controller`](include/controller.rb) - Controller-specific monitoring

## Usage Patterns

### Service Integration

```ruby
class MyService
  def initialize
    @monitor = Logging::Monitor.new('my-service')
  end

  def perform_operation
    @monitor.track_request(:info, 'Starting operation', 'my_service.start')

    result = do_work

    @monitor.track_request(:info, 'Operation successful', 'my_service.success')
    result
  rescue StandardError => e
    @monitor.track_request(:error, "Operation failed: #{e.message}",
                          'my_service.error', error: e.message)
    raise
  end
end
```

## Features

### Automatic PII Filtering

#### Global structured metadata scrubbing

All structured metadata passed to `Rails.logger` is automatically scrubbed before
logs are emitted. This applies to hash payloads such as keyword arguments:

- **Production:** [`PIIFilteringFormatter`](../semantic_logger/pii_filtering_formatter.rb)
  extends `SafeJsonFormatter` for structured JSON logs.
- **Development:** [`PIIFilteringColorFormatter`](../semantic_logger/pii_filtering_color_formatter.rb)
  extends SemanticLogger's color formatter so console/foreman output stays
  human-readable (`Rails -- message -- { :key => "value" }`) while still scrubbing
  payload values.

Both formatters share scrubbing logic via
[`PIIPayloadScrubber`](../semantic_logger/pii_payload_scrubber.rb).

```ruby
# PII in payload values is redacted automatically
Rails.logger.info('User action', ssn: '123-45-6789', icn: '1234567890V123456')

# Nested hashes and arrays are scrubbed recursively
Rails.logger.info(
  'User profile',
  user: { contact: { email: 'john@example.com', phone: '555-123-4567' } }
)

# Per-call allowlist to preserve specific fields when needed
Rails.logger.info('User action', ssn: '123-45-6789', safe_keys: [:ssn])
```

Scrubbing walks nested hashes and arrays recursively. A `safe_keys` entry applies to
any payload key with that name at any depth (for example, `:email` under `user.contact`
is redacted unless `email` is listed in `safe_keys`).

`safe_keys` is stripped from the log output and is not persisted. See
[`Logging::Helper::DataScrubber`](helper/data_scrubber.rb) for the
full list of detected PII patterns.

#### Bypassing filtering with `safe_keys`

Use `safe_keys` only when a payload field is **intentionally non-PII** but matches
a scrubbing pattern (for example, a numeric ID that looks like an SSN). Default to
redaction; opt out per log call when you have a documented reason.

**Rails.logger (per-call allowlist)**

Pass `safe_keys` as a keyword argument alongside the fields to log. The formatter
removes `safe_keys` from the emitted payload so it never appears in logs.

```ruby
# Single field preserved; all other payload values are still scrubbed
Rails.logger.info(
  'Claim submitted',
  claim_reference: '123-45-6789',
  veteran_email: 'vet@example.com',
  safe_keys: [:claim_reference]
)
# => claim_reference preserved, veteran_email => [REDACTED], safe_keys omitted

# Multiple fields
Rails.logger.info('Debug context', field_a: '555-123-4567', field_b: '123-45-6789',
                  safe_keys: %i[field_a field_b])

# String key for safe_keys also works
Rails.logger.info('Debug context', ssn: '123-45-6789', 'safe_keys' => [:ssn])
```

Allowlisted field names can be symbols or strings; matching is done on the
string form of the key (`:ssn` and `'ssn'` are equivalent). The same key name is
honored at any nesting depth (top-level and nested `custom_safe_field` are both
preserved when listed in `safe_keys`).

**Always-protected keys (no opt-out needed)**

These keys are never scrubbed by [`DataScrubber`](helper/data_scrubber.rb)
and do not require `safe_keys`:

`claim_id`, `confirmation_number`, `form_id`, `id`, `in_progress_form_id`,
`saved_claim_id`, `submission_id`, `user_account_uuid`, `tags`, `response_code`,
`completely_removed`, `removed_keys`

**Logging::Monitor (service-level allowlist)**

For monitors that scrub context before logging, pass `safe_keys` when creating the
monitor instance. Those keys apply to every `track_request` call for that monitor:

```ruby
monitor = Logging::Monitor.new('my-service', safe_keys: %w[external_reference_id])

monitor.track_request(
  :info,
  'Downstream reference',
  'my_service.reference',
  external_reference_id: '123-45-6789' # preserved via monitor safe_keys
)
```

Per-call `safe_keys` on `Rails.logger` and monitor-level `safe_keys` are
independent. Monitor safe keys do not need to be repeated in each log call.

**What `safe_keys` does not do**

- Does not scrub or bypass filtering for the **log message string** — only hash
  payload values. Avoid embedding PII in the message; put context in the payload.
- Does not apply to request params (`filter_parameter_logging.rb` is separate) or
  log tags such as `referer`.
- Does not disable scrubbing globally. Each call must name the specific keys to
  preserve.

**Review guidance**

Treat `safe_keys` like a code review flag. Reviewers should confirm the named
fields cannot contain veteran PII before approving the bypass.

#### Logging::Monitor context filtering

`Logging::Monitor` also scrubs context parameters before logging (redundant with
the global formatter but safe and idempotent):

```ruby
monitor.track_request(:info, 'User action', 'user.login',
                     email: 'user@example.com',  # Will be filtered
                     ssn: '123-45-6789')         # Will be filtered
```

### StatsD Integration

Every `track_request` call automatically:
- Increments the specified metric in StatsD
- Adds service and function tags
- Includes any custom tags provided

### Structured Logging

Log entries include consistent metadata:
- Service name
- Function name
- File and line number
- Filtered context parameters
- StatsD metric name

## Best Practices

### Service Naming

Use consistent, descriptive service names:
- `claims-evidence-api` - for [`ClaimsEvidenceApi::Monitor`](modules/claims_evidence_api/lib/claims_evidence_api/monitor.rb)
- `decision-reviews` - for decision review operations
- `benefits-intake` - for document uploads

### Error Levels

Choose appropriate log levels:
- `:info` - Normal operations, successful completions
- `:warn` - Unexpected but recoverable conditions
- `:error` - Errors that affect operation but allow continuation
- `:fatal` - Critical errors that may cause service failure

### Metrics Naming

Follow DataDog conventions:
- Use dots to separate namespaces: `service.operation.result`
- Include relevant tags for filtering
- Keep metric names descriptive but concise

## Integration Examples

The logging utilities are used throughout vets-api:

- **Claims Evidence API**: [`ClaimsEvidenceApi::Monitor`](modules/claims_evidence_api/lib/claims_evidence_api/monitor.rb)
- **Decision Reviews**: [`DecisionReviews::V1::LoggingUtils`](modules/decision_reviews/lib/decision_reviews/v1/logging_utils.rb)
- **Claims API**: [`ClaimsApi::Logger`](modules/claims_api/lib/claims_api/claim_logger.rb)
- **Zero Silent Failures**: [`ZeroSilentFailures::Monitor`](lib/zero_silent_failures/monitor.rb)

This centralized approach ensures consistent logging across all VA.gov services while protecting veteran PII and providing actionable metrics for monitoring and debugging.
