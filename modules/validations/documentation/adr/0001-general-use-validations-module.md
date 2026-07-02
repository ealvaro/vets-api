# 1. General Use Validations Module

Date: 2026-06-22

## Status

Accepted

## Context

The 526EZ form currently validates zip codes by calling `GET /income_limits/v1/validateZipCode/:zip`. That endpoint lives in the `income_limits` module and is owned by another team — we're borrowing it as a temporary workaround

Pull this into a single shared endpoint that both income_limits and 526EZ (and any future team) can call, rather than 526EZ depending on another team's namespaced route.

The underlying pieces already exist:

- `std_zipcodes` table (~42k rows), populated by `IncomeLimits::StdZipcodeImport`
- `StdZipcode` model, currently in `modules/income_limits`
- The validation logic itself is trivial: does a row exist for this zip → `{ zip_is_valid: true/false }`

**What needs to happen:**

1. Promote the lookup to a shared home so it's not owned by income_limits
   - A small shared module/service if there's a preferred pattern for cross-team utilities.
   - The `StdZipcode` model likely needs to move out of `modules/income_limits` **future work**
2. Keep the response shape identical (`{ zip_is_valid: true/false }`) and keep it unauthenticated, matching the current endpoint — so it's a drop-in.

## Decision

A shared module/service for cross-team utility.  Moving the existing Std#### models from `income_limits`.

## Consequences

**Frontend follow-up (us):** once the shared endpoint exists, it's a one-line URL swap in `ZipCodeInput.jsx` — no other changes.
`ZipCodeInput.jsx` pointing here: <https://va.ghe.com/software/vets-website/pull/45374/changes#diff-4276605227eb0a66781f48efcb89041ec2ac4981aa1d1a4e71302edb2aa4206bR28>

Migrate income_limits' existing usage to the new shared endpoint, then deprecate the old `validateZipCode` route once both teams are off it.
