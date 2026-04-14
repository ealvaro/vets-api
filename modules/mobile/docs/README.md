# Mobile API Documentation

This directory contains the OpenAPI specification and documentation for the VA Mobile API.

## Files

- `openapi.yaml` - Source of truth for API documentation (edit this file). Also the file hosted for our OpenAPI specs via Docusaurus on the va-mobile-app repo.
- `openapi.json` - Generated JSON version of the spec (auto-generated, do not edit). Used by the Committee gem for schema validation in RSpec.
- `index.html` - Generated static HTML documentation for local browsing only (gitignored, not committed to the repo)
- `schemas/` - Reusable schema definitions referenced in openapi.yaml
- `examples/` - Example request/response payloads
- `params/` - Reusable parameter definitions
- `generate_static_docs.sh` - Script to manually generate static docs locally
- `validate_route_coverage.rb` - Script to validate all routes are documented

## Automated Documentation Generation

When you modify `openapi.yaml`, `routes.rb`, schemas, examples, or params in a pull request, a GitHub Action automatically:

1. **Validates route coverage** - Ensures all routes in `config/routes.rb` are documented in `openapi.yaml`
   - Uses flexible parameter matching (e.g., `{id}` in routes matches `{appointmentId}` in OpenAPI)
   - Fails the build if undocumented routes are found
2. **Generates openapi.json** - Bundles `openapi.yaml` into `openapi.json`
3. **Commits changes** - Automatically commits the generated file to your PR branch

This means you only need to edit `openapi.yaml` and related schema files - `openapi.json` is generated for you!

## Manual Generation

If you need to generate `openapi.json` locally:

```bash
cd modules/mobile/docs
redocly bundle openapi.yaml -o openapi.json
```

To also generate `index.html` for local browsing:

```bash
cd modules/mobile/docs
./generate_static_docs.sh
```

Note: You may need to install `redocly` first:

```bash
npm install -g @redocly/cli
```


## Validating Route Coverage

To check if all routes are documented:

```bash
cd modules/mobile/docs
ruby validate_route_coverage.rb ../config/routes.rb openapi.yaml
```

This will exit with an error code and list any undocumented routes.

### Parameter Matching

The validation script uses flexible parameter matching, which means:
- Routes like `/appointments/cancel/:id` in `routes.rb` will match `/appointments/cancel/{cancelId}` in `openapi.yaml`
- Parameter names don't need to be identical - any path parameter matches as long as it's in the same position
- This allows for more descriptive parameter names in the OpenAPI spec (e.g., `{appointmentId}`, `{facilityId}`) while keeping simpler names in routes

## Adding New Routes

When you add a new route to `config/routes.rb`:

1. Add the corresponding path and methods to `openapi.yaml`
2. Create a PR - the GitHub Action will validate and generate docs automatically
3. If routes are missing from the OpenAPI spec, the action will fail and list them

## Schema Validation in Tests

Use `assert_schema_conform` from `CommitteeHelper` to validate API request and response bodies
against the OpenAPI spec (`openapi.json`) in request specs:

```ruby
require_relative '../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::MyEndpoint', type: :request do
  include CommitteeHelper

  it 'returns a valid response' do
    get '/mobile/v0/my-endpoint', headers: sis_headers
    assert_schema_conform(200)
  end
end
```

This validates both the request and response against the OpenAPI spec, ensuring the documentation
stays in sync with the actual API behavior.

Do **not** use `match_json_schema` for API request/response validation — it validates against
standalone JSON schema files and does not verify OpenAPI spec accuracy. `match_json_schema` is
reserved for validating non-response JSON (e.g., log output structure).

## Viewing Documentation

`index.html` is gitignored and not committed to the repo. To view the documentation locally, generate it first using `./generate_static_docs.sh`, then either right-click the file and open it in a browser, or copy the absolute file path and paste it into the browser.
