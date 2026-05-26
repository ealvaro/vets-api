# Swagger API Documentation

## Hosted Docs

[SwaggerUI is hosted on GitHub Pages](https://software-vets-api.pages.va.ghe.com/#/)

The docs are automatically regenerated and redeployed on every push to `master` via [`.github/workflows/deploy-swagger-ui.yml`](../../.github/workflows/deploy-swagger-ui.yml).

### How it works

At deploy time, the workflow:

1. Boots the Rails app in `development` mode (with a Redis service container for Sidekiq)
2. Runs `rails runner` to call `Swagger::Blocks.build_root_json(V0::ApidocsController::SWAGGERED_CLASSES)` and write the output to `public/api-reference/apidocs.json`
3. Updates `public/api-reference/index.html` to load `./apidocs.json` instead of the old live `dev-api.va.gov` endpoint (which was blocked by CORS)
4. Deploys the contents of `public/api-reference/` to the `gh-pages` branch via `peaceiris/actions-gh-pages`

The static Swagger UI assets live in `public/api-reference/`. The generated `apidocs.json` is not committed to the repo — it is produced fresh on each deploy from the code on `master`.

> **Note:** The `/v0/apidocs` route is disabled in `production` and `staging` environments. The GitHub Pages deployment is the canonical way to access the Swagger 2.0 docs for those environments.

## Viewing Docs Locally

Go to `http://localhost:3000/v0/swagger/` and use "Select a definition" in the upper right corner.

## API Endpoints

| Format | Endpoint | Notes |
|--------|----------|-------|
| Swagger 2.0 | `GET /v0/apidocs` | Available in `development` only; disabled in `production`/`staging` |
| OpenAPI 3.0 | `GET /v0/openapi` | |

Module-level APIs (e.g. `claims_api`, `appeals_api`) use RSwag and have their own committed `swagger.json` files under `modules/<name>/app/swagger/`.