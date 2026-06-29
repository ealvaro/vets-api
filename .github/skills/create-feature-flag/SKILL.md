---
name: create-feature-flag
description: 'Create a new Flipper feature flag in vets-api. Use when adding, registering, or scaffolding a feature toggle in config/features.yml, or when gating new functionality behind a Flipper flag for a controlled rollout.'
argument-hint: 'flag_name (e.g. disability_526_new_start_experience_enabled)'
---

# Create a Flipper Feature Flag in vets-api

## When to Use
- User asks to add, create, or register a feature flag or feature toggle
- User wants to gate new functionality behind a Flipper flag
- User is working on a controlled or incremental rollout

## Procedure

### 1. Determine the flag name

If the user passed an argument (e.g. `/create-feature-flag disability_526_new_start_experience_enabled`), use that as the flag name and proceed directly to step 2. Do not ask for the name again.

If no argument was provided, ask the user for the flag name before proceeding.

**Validate the flag name** before proceeding. A valid flag name:
- Is `snake_case` only — lowercase letters, digits, and underscores
- Does not contain uppercase letters, hyphens, or spaces

If the provided name is invalid, do **not** proceed. Instead:
1. Show the user what's wrong (e.g. "wrongCase contains uppercase letters")
2. Suggest the corrected `snake_case` version (e.g. `wrong_case`)
3. Ask the user to confirm before continuing

Use `snake_case`. Name after the feature/product area, not an implementation detail. Follow existing prefix conventions:

| Product area | Prefix example |
|---|---|
| Form 21-526EZ | `disability_526_` |
| MyHealtheVet | `my_health_` |
| Mobile | `mobile_` |

If not provided, ask the user for the flag name before proceeding.

### 2. Confirm description

Ask the user the following question and **stop**. Wait for the user's reply before continuing to step 3.

> **What should the flag description say?**
>
> This is shown to admins in the Flipper UI when deciding whether to toggle the flag. Write it as a plain-English sentence that explains what changes when the flag is **on** — not what the code does internally.
>
> Good example: `If enabled, Form 21-526EZ will use the new start experience instead of the wizard on the first page of the form.`
> Poor example: `Enables the new flow.`
>
> Reply with your description text.

Use the description exactly as provided by the user.

### 3. Confirm advanced options

After receiving the description, present the following summary and **stop**. Wait for the user's reply before continuing.

> The remaining two fields have recommended defaults for most flags:
>
> | Field | Default | What it means |
> |---|---|---|
> | `actor_type` | `user` | Flag is evaluated per logged-in veteran. Use `cookie_id` instead when the flag is read in any **unauthenticated** request flow — not just pre-login pages (landing pages, banners) but also features that hit endpoints served without sign-in (e.g. a controller with `skip_before_action :authenticate`). A `user` actor can't be resolved for logged-out visitors, so percentage rollouts won't reach them. |
> | `enable_in_development` | `false` | Flag is off everywhere until explicitly enabled in the Flipper UI — the right choice for a controlled rollout. Set to `true` only if you want it always-on for local `development` and on `dev-api.va.gov`. Note: the `test` env auto-enables all new flags regardless of this setting. |
>
> **Would you like to use the defaults?** Reply `yes` to proceed with `actor_type: user` and `enable_in_development: false`, or `no` to configure each field individually.

- If the user replies `yes`: use `actor_type: user` and `enable_in_development: false`, then proceed to step 5.
- If the user replies `no`: proceed to step 4.

### 4. Configure each field individually

#### 4a. Confirm actor_type

Ask the user the following question and **stop**. Wait for the reply before asking about `enable_in_development`.

> **Who is this flag checked against?**
>
> - **`user`** *(recommended)* — Evaluated per logged-in veteran. Targets individual users by UUID or email.
> - **`cookie_id`** — Evaluated using the Google Analytics cookie ID. Works for unauthenticated visitors. Use whenever the flag is read in an unauthenticated request flow — pre-login pages (landing pages, banners) **or** features that call endpoints served without sign-in (e.g. a controller with `skip_before_action :authenticate`). A `user` actor can't be resolved when logged out, so percentage rollouts won't apply to anonymous visitors.
>
> Reply with `user` or `cookie_id`.

#### 4b. Confirm enable_in_development

Ask the user the following question and **stop**. Wait for the reply before proceeding to step 5.

> **Should this flag be auto-enabled in development and test environments?**
>
> - **`false`** *(recommended)* — Off everywhere until an admin enables it in the Flipper UI. Use for controlled rollouts.
> - **`true`** — Automatically on in local `development` and on `dev-api.va.gov`. Note: the `test` env auto-enables all new flags regardless of this setting.
>
> Reply with `true` or `false`.

### 5. Find the correct insertion point in `config/features.yml`

The file is sorted **alphabetically**. Use `grep_search` to find the neighbouring flags on either side of the new name, then insert in the correct position. Do **not** append to the end.

```
# Example: disability_526_new_start_experience_enabled
# comes after disability_526_new_bdd_sha_enforcement_workflow_enabled
# comes before disability_526_form_navigation_menu
```

### 6. Insert the entry

Using the flag name, `actor_type`, description, and `enable_in_development` confirmed above:

```yaml
  your_flag_name_here:
    actor_type: user          # or cookie_id
    description: If enabled, [description provided by user].
    enable_in_development: false  # or true
```

### 7. Verify the insertion

Read back the surrounding lines to confirm:
- Alphabetical ordering is correct
- YAML indentation is correct (2-space for flag name, 4-space for fields)

### 8. Confirm Flipper UI registration

No additional steps needed. `config/initializers/flipper.rb` reads `features.yml` at boot and calls `Flipper.add(feature)` for any flag not yet in the database. After restarting the server, the flag appears in the Flipper UI at `/flipper`.
