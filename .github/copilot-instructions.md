# Copilot Instructions for `vets-api`

## Repository Context
`vets-api` is a Ruby on Rails API serving veterans via VA.gov. Large codebase (400K+ lines) with modules for appeals, claims, healthcare, and benefits processing.

**Default Branch:** `master` - All code reviews and comparisons should be against the `master` branch
**Key External Services:** BGS, MVI, Lighthouse APIs
**Architecture:** Rails engines in `modules/`, background jobs via Sidekiq Enterprise

## For Copilot Chat - Development Help

### Quick Commands
- **Test**: `bundle exec rspec spec/` or `make spec`
- **Test with logging**: `RAILS_ENABLE_TEST_LOG=true bundle exec rspec path/to/spec.rb` (logs to `log/test.log`)
- **Test parallel**: `make spec_parallel` (faster for full test suite)
- **Lint**: `bundle exec rubocop` (handled by CI, don't suggest fixes)
- **Server**: `foreman start -m all=1`
- **Console**: `bundle exec rails console`
- **DB**: `make db` (setup + migrate)

### Quick Reference
- **Config files**: `modules/[name]/config/` or main `config/`
- **Serializers**: End controllers with `render json: object, serializer: SomeSerializer`
- **Auth**: Most endpoints need `before_action :authenticate_user!`
- **Jobs**: Use `perform_async` for background work, `perform_in` for delayed

### Common Patterns
- Controllers in `modules/[name]/app/controllers` or `app/controllers`
- Background jobs in `app/sidekiq/` - use for operations >2 seconds
- External service clients in `lib/` with Faraday configuration
- Feature flags via Flipper for gradual rollouts and A/B testing `config/features.yml`
- Strong parameters required - never use `params` directly
- Error responses use envelope: `{ error: { code, message } }`
- Service objects return `{ data: result, error: nil }` pattern

### Module Structure (Rails Engines)
- Each module in `modules/` is a Rails engine with its own namespace
- Module controllers inherit from `ApplicationController` or their module's base controller
- Module routes defined in `modules/[name]/config/routes.rb`
- Module configs in `modules/[name]/config/`
- Shared code belongs in main `app/` or `lib/` directories
- Module-specific serializers in `modules/[name]/app/serializers/[namespace]/`

### Key Dependencies
- PostGIS required for database
- Sidekiq Enterprise (may need license)
- VCR cassettes for external service tests
- Settings: `config/settings.yml` (alphabetical order required)

### Settings Value Handling

**⚠️ CRITICAL: Treat Settings values like untrusted user input.** Settings values from Parameter Store may arrive as unexpected types. The `config` gem (`config/initializers/config.rb`) has `env_parse_values = true`, which automatically converts numeric strings to integers (e.g., `"0"` becomes `0`). Always use explicit type coercion and safe fallbacks.

When reviewing pull requests that use Settings values, only comment if the value is used in a boolean or integer context without safe type coercion (see Unsafe patterns below) — for example, a bare `if Settings.x.y`, an `== true` comparison, or an unguarded `.to_i`/numeric use without a fallback. Do not comment if the code already uses one of the Safe patterns below (`ActiveModel::Type::Boolean.new.cast()`, explicit `.to_s.downcase == 'true'`, `.present?`/`.blank?`, or `.to_i` with a fallback) — this is already correct and should not be flagged.

**Common Pitfalls:**
- Numeric strings are auto-converted: `"0"` → `0`, `"123"` → `123` (via `env_parse_values`)
- `0` (integer zero) is truthy in Ruby - only `false` and `nil` are falsy
- `"false"` (string) is truthy - only boolean `false` and `nil` are falsy
- `Settings.some.value == true` fails when value is the string `"true"` or integer `1`

**❌ Unsafe patterns:**
```ruby
if Settings.feature.enabled        # Fails: 0 is truthy, "false" is truthy
if Settings.feature.enabled == true # Fails if value is "true" or 1
timeout = Settings.api.timeout     # May be nil, wrong type, or unexpected value
```

**✅ Safe patterns:**
```ruby
# For booleans - use ActiveModel::Type::Boolean for robust casting
# Handles: true, false, "true", "false", 1, 0, "1", "0", nil
if ActiveModel::Type::Boolean.new.cast(Settings.feature.enabled)

# Alternative: explicit string comparison
# Returns true only for "true" (case-insensitive), false for everything else including nil, 0, 1
if Settings.feature.enabled.to_s.downcase == 'true'

# For integers - always convert with safe fallback
timeout_value = Settings.api.timeout.to_i
timeout = timeout_value.positive? ? timeout_value : 30

# For presence checks - use .present? or .blank?
if Settings.api.url.present?
```

### Gemfile and Dependency Management
- **DO NOT commit Gemfile or Gemfile.lock changes** unless they are necessary for the feature/fix you are implementing
- **DO NOT commit local Gemfile modifications** that remove the `sidekiq-ent` and `sidekiq-pro` gems (these may be removed locally if you don't have a Sidekiq Enterprise license, but should never be committed)
- Gemfile.lock changes from running `bundle install` to get your local dev environment working should NOT be committed
- Only commit Gemfile changes when adding, removing, or updating gems as part of your feature work
- Ruby and gem versions are defined in `Gemfile` and locked in `Gemfile.lock`
- If you need a newer version of a gem, submit a draft PR with just the gem updated and passing tests

### VA Service Integration
- **BGS**: Benefits data, often slow/unreliable
- **MVI**: Veteran identity, use ICN for lookups
- **Lighthouse**: Modern REST APIs for claims, health records, veteran verification

## For PR Reviews - Human Judgment Issues

### ⚠️ NO DUPLICATE COMMENTS - Consolidate Similar Issues

### Priority Order
The four categories below are ordered by priority: **Security & Privacy > Business Logic > Anti-Patterns > Architecture.** If a PR has issues across multiple categories, surface all of them — priority order is for tie-breaking, not for skipping lower categories. But if you're re-reviewing a PR across multiple pushes and need to decide what's most important to flag first, or a genuinely large PR would produce an excessive number of comments, keep to this order: never drop a Security finding to make room for an Architecture one.

### Surface Findings — Don't Suppress on Low Confidence
If you identify a genuine issue matching any category below, post it as a normal, visible review comment. Do not move findings into a collapsed "low confidence" section as a way to hedge — human reviewers will not expand collapsed sections, so a suppressed comment is equivalent to not reviewing the code at all.

- If you're confident an issue matches one of the categories below (Security, Business Logic, Anti-Patterns, Architecture), comment on it directly and normally.
- If you're uncertain whether something is actually a bug (not just uncertain how to phrase it), say so plainly in the comment itself — e.g., "This may be intentional, but X doesn't handle Y — worth confirming." A hedged, visible comment is correct. A confident-sounding comment hidden in a collapsed section is not.
- Only omit a finding entirely if it falls outside the categories in this document (see "Trust These Guidelines" below) — not because you're unsure how strong the finding is.

### Security & Privacy Concerns
**⚠️ Highest priority category — PII/PHI exposure directly harms veterans.** Always surface these even if it means a shorter review elsewhere.
- **PII in logs**: Check for email, SSN, medical data in log statements
- **Hardcoded secrets**: API keys, tokens in source code
- **Missing authentication**: Controllers handling sensitive data without auth checks
- **Mass assignment**: Direct use of params hash without strong parameters
- **Removed security controls**: PRs that disable or remove existing security checks (e.g., virus scanning, validation, encryption) without a documented compensating control

### Business Logic Issues
- **Non-idempotent operations**: Creates without duplicate protection
- **Blocking operations in controllers**: sleep(), File.read, document processing, operations >2 seconds
- **Wrong error response format**: Not using VA.gov standard error envelope
- **Service method contracts**: Returning `{ success: true }` instead of data/error pattern

### Anti-Patterns
- **New logging without Flipper**: Logs not wrapped with feature flags
- **External service calls**: Missing error handling, timeouts, retries, or rescue blocks
- **Background job candidates**: File.read operations, PDF/document processing, bulk database updates, .deliver_now emails
- **Wrong identifier usage**: Using User ID instead of ICN for MVI/BGS lookups
- **Form handling**: Complex forms not using form objects for serialization
- **Unnecessary Gemfile changes**: Committing Gemfile/Gemfile.lock changes that are not required for the feature (e.g., local dev environment setup changes, removal of sidekiq-ent/sidekiq-pro gems)
- **Unsafe Settings usage**: Using Settings values in boolean context without `ActiveModel::Type::Boolean.new.cast()` - values may be strings, integers, or nil due to Parameter Store and `env_parse_values`
- **Timezone mismatch in tests**: Tests using `Time.zone.today`, `Date.today`, or `Date.current` in the default `Time.zone` (often UTC in tests/CI) when the production code computes dates in an explicit application timezone (e.g., `Time.use_zone('Eastern Time (US & Canada)') { Date.current }`). Tests must use the same timezone configuration as the code under test to avoid off-by-one flaky failures that only occur when CI runs between midnight UTC and midnight in the target timezone.

### Architecture Concerns
- **N+1 queries**: Loading associations in loops without includes
- **Response validation**: Parsing external responses without checks
- **Method complexity**: Methods with many conditional paths or multiple responsibilities
- **Database migrations**: Mixing index changes with other schema modifications; index operations missing `algorithm: :concurrently` and `disable_ddl_transaction!`

## Consolidation Examples

**Good PR Comment:**
```
Security Issues Found:
- Line 23: PII logged (user email)
- Line 45: Hardcoded API key
- Line 67: Missing authentication check
Recommend: Remove PII, move key to env var, add before_action
```

**Bad PR Comments:**
- Separate comment for each security issue
- Flagging things RuboCop catches (style, syntax)
- Repeating same feedback in different words

## Testing Patterns

### Test Organization
- **Request specs**: In `spec/requests/` for API endpoint testing
- **Unit specs**: In `spec/models/`, `spec/services/`, etc. for isolated component testing
- **Module specs**: In `modules/[name]/spec/` for module-specific functionality
- **Factories**: Use FactoryBot factories in `spec/factories/` or `modules/[name]/spec/factories/`
- **VCR cassettes**: For external API responses in `spec/fixtures/` or module equivalent

### Test Conventions
- Use `let` for test data setup, avoid instance variables
- Stub external services with VCR or custom stubs
- Test both success and failure scenarios for external service calls
- Include edge cases: empty responses, timeouts, malformed data
- Use descriptive test names that explain the expected behavior

## Context for Responses
- **VA.gov serves millions of veterans** - reliability and security critical
- **External services often fail** - VA systems like BGS/MVI require resilient retry logic
- **PII/PHI protection paramount** - err on side of caution for sensitive data
- **Performance matters** - veterans waiting for benefits decisions
- **Feature flags enable safe rollouts** - wrap new features and risky changes
- **Idempotency critical** - duplicate claims/forms cause veteran issues
- **Error logging sensitive** - avoid logging veteran data in exceptions

## Trust These Guidelines
These instructions focus on issues requiring human judgment that automated tools can't catch. Don't suggest fixes for style/syntax issues - those are handled by CI.

## Tool Calling Efficiency
You have the capability to call multiple tools in a single response. For maximum efficiency, whenever you need to perform multiple independent operations, ALWAYS call tools simultaneously whenever the actions can be done in parallel rather than sequentially.

Especially when exploring repository, searching, reading files, viewing directories, validating changes, reporting progress or replying to comments. For example you can read 3 different files in parallel, or report progress and edit different files in parallel. Always report progress in parallel with other tool calls that follow it as it does not depend on the result of those calls.

However, if some tool calls depend on previous calls to inform dependent values like the parameters, do NOT call these tools in parallel and instead call them sequentially.
