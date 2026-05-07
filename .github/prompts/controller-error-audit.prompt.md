---
description: "Audit controller rescue blocks for misclassified errors. Use when: controller error audit, 500 error check, upstream error audit, rescue review, error handler audit"
argument-hint: "Path to scan (e.g., modules/pensions, modules/*, app/controllers/v0/claim_letters_controller.rb)"
agent: "agent"
tools: [read, search]
---

# 500 Error Audit

You are auditing Ruby controller files for misclassified upstream errors that surface as 500s in DataDog. Work through every step below **in order** for each controller file found at the path the user provides.

**You are READ-ONLY. DO NOT edit any files. Present all suggestions as Ruby code blocks the user can apply themselves.**

## Important Constraints

- **DO NOT edit, create, or modify any files.** Only read and search.
- **DO NOT assume knowledge of previous file edits.** Read every file fresh.
- **DO NOT suggest changing existing error message strings, StatsD keys, or metric names.** Changing these disrupts DataDog dashboards and monitors.
- If the user provides a DataDog error class/message, use it to prioritize which error types to check first.

## Context-Gathering Rules

Before making any classification judgment, you MUST:

1. **Read the full method** — not just the rescue line. Understand what the method does, what service it calls, and what the happy path returns. A rescue block only makes sense in the context of the method it protects.

2. **Read included concerns and shared error handlers first** — before suggesting controller-local changes, check whether the controller includes error-handling concerns (e.g., `include ErrorHandler`, `include ExceptionHandling`). Read those concern files. The fix may already exist there, or the correct fix may belong there instead of in the controller.

3. **Check for existing status mappers** — look for methods like `error_status_from`, `status_for`, or hash-based status mappings already in the controller or its concerns. If one exists, suggest additions to it rather than inline rescue changes.

4. **Determine error ownership before choosing a status code:**
   - **User error** (bad input, missing params, unauthorized) → 4xx
   - **System/upstream error** (external service failed, timed out, returned garbage) → 502/503/504
   - **Our bug** (genuinely unexpected, logic error in our code) → 500
   - **Not clearly classifiable** → see exit ramp below

5. **Exit ramp: skip unclear findings** — if after reading the full method, its concerns, and the error class hierarchy you cannot confidently determine the correct status code, **skip the finding**. Report it in the summary as "Needs manual review" with a brief explanation of why classification is ambiguous. Do NOT guess.

## Step 1: Discover Controller Files

Find all `*_controller.rb` files under the provided path. For each controller, also find:
- Any error handler concerns it includes (e.g., `include ErrorHandler`, `include FacilitiesErrorHandler`)
- The shared concern file itself (this is often where rescue logic lives)

List what you found before proceeding.

## Step 2: Audit Rescue Clauses

For each controller and its error handler concern, check every `rescue` block and verify:

**Deduplication rule:** If the same rescue comes from a shared concern included by multiple controllers, report it once under the concern and list affected controllers.

### Upstream errors (should be 502 Bad Gateway, 503 Service Unavailable, or 504 Gateway Timeout — NOT 500):
- `Common::Client::Errors::ClientError` → 502 (or 503 if nil/zero status)
- `Common::Client::Errors::ParsingError` → 502
- `JSON::ParserError` → 502 (upstream returned HTML/garbage instead of JSON). Only classify as 502 when parsing an upstream response; request-body parse errors should remain 400/422.
- `Common::Exceptions::BackendServiceException` → 502
- `Common::Exceptions::GatewayTimeout`, `Timeout::Error`, `Net::ReadTimeout`, `Faraday::TimeoutError` → 504
- `Common::Exceptions::ServiceUnavailable` → 503
- `Breakers::OutageException`, `SocketError`, `OpenSSL::SSL::SSLError` → 503
- `Faraday::ResourceNotFound` → 404 (not 500)
- `VAProfile::VeteranStatus::VAProfileError` → 502 (this is a StandardError subclass that escapes BaseError rescues)

### Application errors (correctly 500):
- `StandardError` catch-all for genuinely unexpected errors → 500

Report any misclassifications you find (e.g., "JSON::ParserError falls through to catch-all → 500, should be 502").

## Step 3: Suggest Rails.logger → Logging::Monitor Replacement

If `Rails.logger.error`, `Rails.logger.warn`, or `Rails.logger.debug` calls exist in the error handling code, suggest replacements using `Logging::Monitor#track_request`.

Show the current code and the suggested replacement as a Ruby code block. For example:

```ruby
# CURRENT:
Rails.logger.error("Some error: #{error.class}")

# SUGGESTED:
monitor.track_request(:error, "Some error: #{error.class}",
                      'some_metric.error',
                      error_class: error.class.name, tags: ["error_class:#{error.class.name}"])
```

If a `monitor` method doesn't exist, suggest one:

```ruby
def monitor
  @monitor ||= Logging::Monitor.new(
    '<service-name>',
    allowlist: %i[error_class resource_name]
  )
end
```

**The exact original log message string must be preserved.** Only suggest changing the delivery mechanism.

## Step 4: Suggest Spec Updates

- Find related spec files for every controller and concern with suggested changes.
- Show any `expect(Rails.logger).to receive(:error)` assertions that need updating.
- Show suggested specs for any newly rescued error types.
- Present each suggestion as a Ruby code block.

## Step 5: Documentation Gaps

List any public methods that are missing `@param` / `@return` YARD docs. Show suggested additions as Ruby code blocks. Keep it minimal — one line per param max.

## Step 6: Rubocop Considerations

Note any lines in your suggestions that might trigger rubocop offenses (e.g., line length, method length). Flag them so the user can address them during implementation.

## Step 7: Summary

Provide a summary table of all findings:

| File | Finding | Severity | Suggested Status Change |
|------|---------|----------|------------------------|
| ... | JSON::ParserError falls to catch-all | High | 500 → 502 |
| ... | Rails.logger.error in json_error | Low | Replace with Monitor |

And list any files that were already correct (no changes needed).
