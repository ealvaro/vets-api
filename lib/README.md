# Shared Services in `lib/`

Before building a new utility, check this list — VFS teams often re-implement solutions that already exist here.

**What counts as "shared"?** A service usable by any team: no coupling to one team's domain models, no team-specific `Settings`, no single-VFS purpose. The archetype is [`Logging::Helper::DataScrubber`](logging/helper/data_scrubber.rb) — a stateless `module_function` module that performs a pure transformation with no DB, HTTP, or team coupling.

This doc deliberately **excludes**:

- **External service clients** (`lib/evss`, `lib/lighthouse`, `lib/mpi`, `lib/bgs`, `lib/mhv`, and ~50 more) — wrappers around upstream VA/partner APIs. They are "shared" in the sense that anyone can call them, but they are integrations, not utilities.
- **Team-specific code** (`lib/disability_compensation`, `lib/hca`, per-form monitors like `lib/form210779`, etc.) — owned by and coupled to a single VFS team's domain.

---

## Shared utilities (service objects)

### Logging, monitoring & PII scrubbing

| Service | Description |
| --- | --- |
| [`logging/helper/data_scrubber.rb`](logging/helper/data_scrubber.rb) | Recursively scrubs PII (SSN, ICN, EDIPI, emails, phone numbers, credit cards, routing numbers…) from strings, hashes, and arrays before logging. Stateless; returns `[REDACTED]` replacements. |
| [`logging/helper/parameter_filter.rb`](logging/helper/parameter_filter.rb) | Rails-style parameter filtering for log payloads. |
| [`logging/monitor.rb`](logging/monitor.rb) + [`logging/base_monitor.rb`](logging/base_monitor.rb) | Base classes for team monitors: one call emits both StatsD metrics and structured Rails logs with consistent tagging. Includes mixins for controllers, Benefits Intake, and zero-silent-failures tracking (`logging/include/`). |
| [`logging/third_party_transaction.rb`](logging/third_party_transaction.rb) | Method-wrapping concern that logs entry/exit and timing around third-party calls. |
| [`semantic_logger/`](semantic_logger/) | Log formatters that scrub PII and guarantee JSON-safe output (`pii_payload_scrubber.rb`, `safe_json_formatter.rb`, plus colorized dev variants). |
| [`string_helpers.rb`](string_helpers.rb) | String utilities: `mask_sensitive`, `hyphenated_ssn`, `capitalize_only`, Levenshtein-based `heuristics`, and endpoint-tag filtering for StatsD. |

### PDF

| Service | Description |
| --- | --- |
| [`pdf_utilities/datestamp_pdf.rb`](pdf_utilities/datestamp_pdf.rb) | Stamps date/text onto any PDF. |
| [`pdf_utilities/pdf_validator.rb`](pdf_utilities/pdf_validator.rb) | Validates PDFs (size, page dimensions, encryption, corruption) with configurable limits. |
| [`pdf_utilities/pdf_stamper.rb`](pdf_utilities/pdf_stamper.rb) | General text/image stamping engine. |
| [`pdf_info.rb`](pdf_info.rb) | Reads PDF metadata via pdfinfo: page count, dimensions, encryption status. |
| [`pdf_fill/`](pdf_fill/) *(engine only)* | Generic hash→PDF-form-fill engine (`pdf_fill/filler.rb`, `pdf_fill/form_value.rb`). The per-form filler classes under `pdf_fill/forms/` are team-specific. |
| [`common/convert_to_pdf.rb`](common/convert_to_pdf.rb) | Converts uploaded images to PDF. |

### Data, dates & formatting

| Service | Description |
| --- | --- |
| [`formatters/date_formatter.rb`](formatters/date_formatter.rb) | Formats dates to iso8601 and human-readable forms. |
| [`formatters/time_formatter.rb`](formatters/time_formatter.rb) | `humanize` — seconds to human-readable durations. |
| [`utilities/date_parser.rb`](utilities/date_parser.rb) | Normalizes many date representations (String, Date, Time, DateTime, hashes) into a `DateTime`. |
| [`common/hash_helpers.rb`](common/hash_helpers.rb) | Deep hash transforms (deep_compact, deep_remove_blanks, key conversion). |
| [`common/file_helpers.rb`](common/file_helpers.rb) | Temp-file helpers: generate, random-name, delete. |
| [`common/validations_patterns.rb`](common/validations_patterns.rb) | Reusable validation regexes. |
| [`json_schema/`](json_schema/) | JSON-schema validation helpers and JSON:API error types (used by form schemas across modules). |

### Encryption & serialization

| Service | Description |
| --- | --- |
| [`aes_256_cbc_encryptor.rb`](aes_256_cbc_encryptor.rb) | AES-256-CBC encrypt/decrypt with HMAC, for symmetric payload encryption. |
| [`json_marshal/`](json_marshal/) | Generic JSON serializer for ActiveRecord `serialize`/Lockbox columns. |
| [`common/jwt_generator.rb`](common/jwt_generator.rb) | Base JWT generation. |

### Messaging & delivery

| Service | Description |
| --- | --- |
| [`slack/`](slack/) | Parameter-driven Slack notifier (`Slack::Service`) — post messages to any channel via webhook. |
| [`sftp_writer/`](sftp_writer/) | Factory returning a local or remote (SFTP) writer from settings — write files without caring about destination. |
| [`common/s3_helpers.rb`](common/s3_helpers.rb) | S3 upload/presign helpers. |
| [`common/virus_scan.rb`](common/virus_scan.rb) | ClamAV scan wrapper for uploaded files. |

### Feature flags

| Service | Description |
| --- | --- |
| [`flipper_utils.rb`](flipper_utils.rb) | `FlipperUtils.safe_enabled?` — check a Flipper flag without raising when Flipper isn't ready (initializers, migrations). |

### Core frameworks

| Service | Description |
| --- | --- |
| [`common/client/`](common/client/) | The HTTP client framework nearly every external integration builds on: `Common::Client::Base`, per-service `Configuration`, breakers integration, and request/response middleware (camelcase, snakecase, JSON parsing, error handling). Start here before hand-rolling Faraday. See [`common/README.md`](common/README.md). |
| [`common/exceptions/`](common/exceptions/) | The shared exception hierarchy (`Common::Exceptions::*`) that maps errors to consistent JSON:API error responses. |
| [`common/models/`](common/models/) | Base model/attribute types, Redis-backed caching concerns, and collection support used by non-DB-backed resources. |
| [`vets/`](vets/) | `Vets::Model` — attribute typing, defaults, and sortable collections for plain-Ruby models (successor to `Common::Base`). See [`vets/README.md`](vets/README.md). |

---

## Framework & infrastructure

Shared by everyone but not "service objects" — platform plumbing you should know exists (and should not re-implement) rather than call day-to-day.

| Service | Description |
| --- | --- |
| [`admin/`](admin/) | Deployment health probes: `RedisHealthChecker`, `DatabaseHealthChecker` (used by ArgoCD checks). |
| [`breakers/`](breakers/) | Circuit-breaker StatsD instrumentation for all outbound services. |
| [`clamav/`](clamav/) | Patched ClamAV client used by `Common::VirusScan`. |
| [`committee/`](committee/) | OpenAPI request/response validation error types. |
| [`core_extensions/`](core_extensions/) | Ruby core-class extensions (e.g. `ImmutableString`). |
| [`faraday_adapter_socks/`](faraday_adapter_socks/) | Faraday adapter for SOCKS proxies. |
| [`flipper/`](flipper/) | Feature-flag admin UI plumbing: route authorization, instrumentation, utilities. |
| [`github_authentication/`](github_authentication/) | GitHub-org-based authorization constraints for internal web UIs (Sidekiq Web, Coverband). |
| [`kafka/`](kafka/) | Event Bus (Kafka) producer plumbing with Datadog instrumentation. |
| [`generators/`](generators/) | Rails generators for scaffolding new modules (`rails g module`). |
| [`dangerfile/`](dangerfile/), [`rubocop/`](rubocop/), [`tasks/`](tasks/) | CI/lint tooling: Danger checks, custom RuboCop cops, schema camelizer for specs. |

---

## Maintenance

- **Adding a shared utility?** Add a row here in the right category.
- **Found duplication?** Prefer consolidating into the existing service listed here; `lib/` CODEOWNERS (largely `@software/va-platform-backend` for the entries above) can advise.
