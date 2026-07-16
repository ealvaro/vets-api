# CODEOWNERS README

## Overview

`.github/CODEOWNERS` maps files and directories to the teams that own them. GitHub uses these entries to auto-request review from the right team whenever a PR touches a matching path. 

## Rules

1. Only assign the owning team(s) to a file or folder
2. Platform doesn't own VFS team(s) files or folders
3. Prefer assign specific files or globs over folders

### ❌ Incorrect: add va-platform-backend as a co-owner

```
app/models/claims_api @software/lighthouse-dash @software/va-platform-backend
```

When `va-platform-backend` is added to a directory alongside another team, **any new file another VFS team creates inside that directory** is automatically co-assigned to `va-platform-backend` for review too. This:

- Overwhelms `va-platform-backend` with reviews for code it doesn't own
- Creates confusion about who actually owns the code
- Slows down review for the team that does own it

### ✅ Correct: owning team only

```
app/models/claims_api @software/lighthouse-dash
lib/rx @software/mobile-api-team
```

### ✅ Correct: no owning team exists

When no team owns a file (for example, the owning team is defunct), `@software/va-platform-backend` can be added to that file.

```
app/models/some_shared_utility.rb @software/va-platform-backend
```

## Directories with mixed ownership

If a directory contains files owned by different teams, don't assign the directory itself to any one team (or to `va-platform-backend`). Instead, assign specific files or subpaths to their real owners:

```
# Bad
app/models/claims_api # This should not be assigned to one team when multiple teams also own files inside a directory.

# Good
app/models/claims_api/legacy_model.rb @software/lighthouse-dash
app/models/claims_api/new_model.rb @software/some-other-team
```

## Automated Checks

Two scripts run in CI against `.github/CODEOWNERS`:

- **`check_codeowners.sh`** (on PR open/update) fails the build if a changed file (or one of its parent directories) has no CODEOWNERS entry at all.
- **`check_deleted_files.sh`** fails the build if a deleted file's CODEOWNERS entry wasn't cleaned up.

Neither script currently detects the co-owner anti-pattern above, that's enforced through PR review, not automation. Please check for it yourself when reviewing changes to this file.

## A Note on `@software/backend-review-group`

`@software/backend-review-group` is a separate GitHub team still used by the `require_be_approval.yml` workflow to require Backend Engineering approval on PRs. That approval gate is independent of file ownership.

`backend-review-group` is **not** used anywhere in CODEOWNERS anymore. Don't re-add it there, it has no bearing on the approval gate, and reintroduces the same co-owner problem this doc warns against. If a path needs a CODEOWNERS entry and has no specific owning team, use `@software/va-platform-backend` instead.

---

## Support

For issues or questions:
- Reach out in #platform-cop-backend Slack channel

CODEOWNER Docs:
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners

