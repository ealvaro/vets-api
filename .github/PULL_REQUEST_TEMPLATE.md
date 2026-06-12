Keep your PR as a Draft until it's ready for Platform review. A PR is ready for Platform review when it has a teammate approval and tests, linting, and settings checks pass CI. See [these tips](https://depo-platform-documentation.scrollhelp.site/developer-docs/vets-api-pr-tips) on how to avoid common delays in getting your PR merged.

## Summary

- *(Summarize the changes that have been made to the platform)*
- *(If bug, how to reproduce)*
- *(What is the solution, why is this the solution?)*
- *(Which team do you work for, does your team own the maintenance of this component?)*

**Is this work behind a feature flag (flipper)?**
- [ ] Yes — flipper name: _(e.g. `my_feature_enabled`)_
- [ ] No — *(briefly explain why, e.g. "low-risk refactor", "hotfix", "no user-facing behavior change")*


## Related issue(s)
*Link your GitHub issue (or screenshot of Jira ticket if your team uses Jira) and any other related issues or PRs*

-

---

## Testing Done

- [ ] New code is covered by unit tests
- [ ] New code is covered by request specs
- *Describe what the old behavior was prior to the change*
- *Describe the steps required to verify your changes are working as expected. Exclusively stating "Specs run" is NOT acceptable*
- *If this work is behind a flipper, tests need to be written for both mocking the flipper on and flipper off scenarios. [Docs](https://depo-platform-documentation.scrollhelp.site/developer-docs/flipper-usage-in-specs).*

## Post-Release Verification

_Platform will use these steps in the event of an outage or OOB incident. A teammate needs to be able to verify your work without tracking you down. You are responsible for verifying your work lands correctly in both staging and production._

- Team Slack Channel (in case someone needs to get in touch regarding this PR):

**Verification steps:**
Staging test user: _(e.g. `vets.gov.user+228@gmail.com` — must have access to the feature being verified)_
- [ ] _(Step 1 — e.g. "Go to https://staging.va.gov/my-va/)_
- [ ] _(Step 2 — e.g. "Click Check claims and Appeals")_
- [ ] _(Step 3 — If behind a flipper, confirm toggle state is correct in production)_
- [ ] _(Add additional steps as needed)_

**Datadog monitors & dashboards:**

| Name | URL | What it tracks |
|------|-----|----------------|
| _(e.g. My Feature Error Rate)_ | _(paste link)_ | _(e.g. 5xx errors for /v0/my_endpoint)_ |
| _(e.g. My Feature Latency Dashboard)_ | _(paste link)_ | _(e.g. p50/p95 latency)_ |

**Expected outcome:**
- _(Describe what a successful release looks like — e.g. "Endpoint returns correct data, no new errors in Datadog")_

## Rollback Plan

_Describe how this change can be reversed if a problem is discovered in production. This section is not optional._

- **Can this be rolled back via flipper?** - [ ] Yes / - [ ] No
- **Rollback steps:**
  - _(e.g. "Disable the `my_feature_enabled` flipper in Flipper UI")_
  - _(e.g. "If no flipper: revert this PR and deploy")_
- **Known risks if rollback is needed:** _(e.g. "DB migration is not reversible — data added during the window will need manual cleanup")_

---

## Acceptance Criteria
- [ ] I fixed|updated|added unit tests and integration tests for each feature (if applicable)
- [ ] No sensitive information (PII/credentials/internal URLs/etc.) is captured in logging, hardcoded, or specs
- [ ] Documentation has been updated _(link to documentation if applicable)_
- [ ] No errors or warnings in the console
- [ ] Events are being sent to the appropriate logging solution
- [ ] Feature/bug has a monitor built into Datadog (if applicable)
- [ ] If app impacted requires authentication, did you login to a local build and verify all authenticated routes work as expected?
- [ ] added a screenshot of the developed feature

---
## Requested Feedback

_(OPTIONAL) What should the reviewers know in addition to the above? Is there anything specific you wish the reviewer to assist with? Do you have any concerns with this PR?_
