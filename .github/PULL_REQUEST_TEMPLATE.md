Keep your PR as a Draft until it's ready for Platform review. A PR is ready for Platform review when it has a teammate approval and tests, linting, and settings checks pass CI. See [these tips](https://depo-platform-documentation.scrollhelp.site/developer-docs/vets-api-pr-tips) on how to avoid common delays in getting your PR merged.

## Summary

- Summarize the changes made to the platform
- If a bug: how to reproduce it
- What is the solution, and why?

**Is this work behind a feature flag (flipper)?**
- [ ] Yes — flipper name: ``
- [ ] No — briefly explain:

## Related issue(s)
-

---

## Testing Done

- [ ] Unit tests added or updated
- [ ] Request specs added or updated
- Describe the old behavior prior to this change
- Describe steps to verify your changes (do not just write "Specs run")
- *If behind a flipper, include tests for both flipper-on and flipper-off scenarios [Docs](https://depo-platform-documentation.scrollhelp.site/developer-docs/flipper-usage-in-specs).*]

## Post-Release Verification

A teammate must be able to verify this work without tracking you down.

- Team Slack Channel (in case someone needs to get in touch regarding this PR):

**Staging test user:**

**Verification steps:**
- Step 1 — e.g. "Go to https://staging.va.gov/my-va/"
- Step 2 — e.g. "Click Check claims and Appeals"
- Step 3 — If behind a flipper, confirm toggle state in production

**Datadog monitors & dashboards:**

| Name | URL | What it tracks |
|------|-----|----------------|
| _(Name)_ | _[url](paste link)_ | _(e.g. 5xx errors for /v0/my_endpoint)_ |
| _(Name)_ | _[url](paste link)_ | _(e.g. p50/p95 latency)_ |

**Expected outcome:**
- Describe what a successful release looks like

## Rollback Plan

- **Rollback via flipper?** — [ ] Yes / [ ] No
- **Steps:**
  -
- **Known risks:**

## Acceptance Criteria
- [ ] Unit and integration tests added for each feature (if applicable)
- [ ] No PII, credentials, or internal URLs in logs, hardcoded values, or specs
- [ ] Documentation updated (link if applicable)
- [ ] No console errors or warnings
- [ ] Events sent to the appropriate logging solution
- [ ] Datadog monitor in place (if applicable)
- [ ] Authenticated routes verified on a local build (if app requires auth)
- [ ] Screenshot of the developed feature attached

---
## Requested Feedback

_(OPTIONAL) What should the reviewers know in addition to the above? Is there anything specific you wish the reviewer to assist with? Do you have any concerns with this PR?_
