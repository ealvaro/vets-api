# Maintenance Windows (PagerDuty)

`vets-api` polls PagerDuty for open maintenance windows and exposes them at
`GET /v0/maintenance_windows`, which the frontend uses to render downtime banners.
Two Sidekiq jobs do the polling:

| Job | What it does |
| --- | --- |
| `PagerDuty::PollMaintenanceWindows` | Queries every configured service and upserts `MaintenanceWindow` records |
| `PagerDuty::CacheGlobalDowntime` | Queries only the `global` service and uploads the result to S3 |

No configuration is required for ordinary development. `config/settings/development.yml`
ships `maintenance.pagerduty_api_token: FAKE`, so polling gets a 401, the jobs log the
error and no-op, and `/v0/maintenance_windows` returns an empty list. Nothing else in the
app depends on it.

## Service IDs

`maintenance.services` maps a setting name to a PagerDuty **service ID** (`P` followed by
six alphanumeric characters). The setting name is what the API reports as
`external_service`, so it has to match what the frontend expects; the ID is account-specific.

Most entries in `config/settings/development.yml` are `~`. Their previous values, retained
in `# was P...` comments, are IDs from the retired **dsva** PagerDuty instance. The
migration to the **ecc** instance did not update this file, so those IDs no longer resolve.

> **One bad service ID fails the entire query.** PagerDuty rejects a
> `GET /maintenance_windows` request with a 400 if *any* `service_ids[]` value doesn't
> exist in the account, so a single stale entry suppresses maintenance windows for every
> correctly configured service. `PagerDuty::Configuration.service_ids` drops `nil`s for
> this reason — leave an entry as `~` rather than guessing at an ID.

Two status codes worth distinguishing when reading logs:

- **401** — the token is missing, fake, or wrong. Says nothing about the service IDs.
- **400** — the token authenticated and PagerDuty rejected the *input*, i.e. at least one
  service ID doesn't exist in that account.

## Finding your service's ID

`PagerDuty::ServicesClient#probe` calls the Get-a-Service endpoint once per configured ID
and reports a per-ID status, so it identifies bad entries without needing PagerDuty UI
permissions — it uses whatever API token the app is configured with:

```bash
bundle exec rails runner 'require "pagerduty/services_client"; pp PagerDuty::ServicesClient.new.probe'
```

`200` means the ID is valid in the token's account, `404` means it isn't, `403` means the
token can't see it, and `nil` means the setting is unset so nothing was sent. The same
diagnostic is available over HTTP at `GET /v0/maintenance_windows/diagnostics`. It's slow —
one request per service — so call it only when investigating.

To list what the account actually contains, `PagerDuty::ExternalServices::Service#get_services`
queries services named with the `maintenance.service_query_prefix` (`External: `). Services
named differently won't appear, so a service missing from that list is not proof its ID is
invalid — confirm with `probe`.

## Enabling it locally

Put a real token and your service's ID in `config/settings.local.yml`, which is loaded after
`config/settings/development.yml` and so overrides it:

```yaml
maintenance:
  pagerduty_api_token: <a PagerDuty REST API key>
  services:
    your_service: P0123AB
```

## Enabling it on a review instance

Review instances run `RAILS_ENV=development`, so they inherit the same
`config/settings/development.yml` values — including the `~` service IDs. They receive a
real token, looked up from SSM by the `review-instance-configure` ansible role, but
**no service IDs**.

If you need your service's maintenance windows to work on a review instance, add it to
`ansible/roles/review-instance-configure/vars/settings.local.yml` in the
[devops](https://va.ghe.com/software/devops) repo, under the existing `maintenance:` key:

```yaml
maintenance:
  pagerduty_api_token: "{{ lookup('aws_ssm_custom', '/dsva-vagov/vets-api/staging/env_vars/maintenance/pagerduty_api_token') }}"
  services:
    your_service: P0123AB
```

Ansible renders that file to `config/settings.local.yml` on the instance, which outranks
`development.yml`. A literal ID is fine — PagerDuty service IDs aren't secrets, and they're
already checked into this repo in plaintext. Use an `aws_ssm_custom` lookup instead only if
you specifically want the value to track SSM.

Two things to keep in mind:

- The token comes from **staging** SSM, so use the ID of the service in that account. Where
  a service exists as both `External: X` and `Staging: External: X`, the staging variant is
  usually what you want on a review instance.
- That file is shared by every review instance, so an incorrect ID there breaks maintenance
  window polling for everyone, per the 400 behavior above. Verify with `probe` on the
  instance after deploying.

## Why service IDs aren't inherited from staging automatically

In deployed `RAILS_ENV=production` environments (staging, prod) the values come from
`config/settings.yml`, which reads them from `maintenance__services__*` environment
variables backed by SSM. There is no `config/settings/production.yml`, so nothing overrides
those.

Review instances are different in two ways: they get almost no environment variables — the
ansible role writes only `VETS_API_USER_ID` and a Sidekiq license into `.env` — and
`config/settings/development.yml` sits above `config/settings.yml` in Config's load order.
So even if those variables were present, the hardcoded development values would win. Only
the ansible-rendered `config/settings.local.yml`, or a `SETTINGS__`-prefixed environment
variable (see `config/initializers/config.rb`), overrides them. That's why opting in is a
deliberate edit to the devops repo rather than something that happens automatically.
