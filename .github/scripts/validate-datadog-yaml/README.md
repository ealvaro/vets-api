# Datadog Service Catalog Workflows

This directory contains the Python validation script and JSON schema used to validate Datadog Service Catalog YAML files, along with documentation for the five GitHub Actions workflows that manage the catalog.

## Validation Script

The script validates any list of YAML files against a provided JSON schema file.

### Usage

Install Python 3.10+, navigate to the script directory, and install the required dependencies:

```shell
$ cd .github/scripts/validate-datadog-yaml
$ pip install -r requirements.txt
```

Call `validate_yaml.py` from the command line:

```shell
$ python validate_yaml.py -s <schemaFilePath> -F <filePathsToValidate>
```

Example:

```shell
$ python validate_yaml.py -s datadog-schema2.2.json -F path/to/file1.yml path/to/file2.yml
```

### Datadog Schema

The schema used for validation (`datadog-schema2.2.json`) is based on the [Datadog Service Catalog v2.2 schema](https://github.com/Datadog/schema/blob/main/service-catalog/v2/schema.json). See the [Datadog Service Definition API docs](https://docs.datadoghq.com/api/latest/service-definition/) for field reference.

---

## Workflows

### `validate-datadog-changes.yml` — Validate changes to Datadog Service Catalog Files

**Trigger:** Pull requests that modify any file matching `datadog-service-catalog/**.yml`

Validates that any added or modified service definition files in a PR conform to the Datadog Service Catalog schema. The workflow:

1. Checks out the repo with enough history to diff against master
2. Sets up Python 3.10 and installs dependencies
3. Diffs the PR branch against master to find added or modified `.yml` files, excluding `datadog-service-catalog.yml`
4. Runs `validate_yaml.py` against those files using `datadog-schema2.2.json`

This is a required status check for PRs. See the note below about the paired skip workflow.

---

### `validate-datadog-changes-skip.yml` — Validate Files Datadog Service Catalog Files

**Trigger:** Pull requests that do **not** modify any file matching `datadog-service-catalog/**.yml`

This workflow exists solely to satisfy GitHub's required status check requirement. When a PR doesn't touch any service catalog files, the validation workflow above never runs — which would leave the required check permanently pending and block the merge.

This workflow runs on the opposite path filter and immediately echoes `PASS -- No files to validate.`, satisfying the status check with no actual work.

**Why two workflows instead of a conditional skip?**

GitHub required status checks must pass on every PR regardless of branch filters. The recommended approach of [skipping via conditionals](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks#handling-skipped-but-required-checks) requires the `github` context to expose the changed file set at the top of the job — which it does not. Since the validation workflow uses a git diff against master, we cannot determine the change set early enough to use a conditional skip reliably.

The solution is two workflows with opposite `paths` / `paths-ignore` filters, both producing a job with the same name. Branch protection sees that job name pass on every PR regardless of which workflow ran.

---

### `datadog_service_catalog_update.yml` — Update Datadog Service Catalog

**Trigger:** Push to `master` that modifies any file matching `datadog-service-catalog/**.yml`

When a PR is merged to master, this workflow pushes any added or modified service definitions to the Datadog Service Catalog via the API. The workflow:

1. Diffs `github.event.before` against `github.event.after` to find added or modified `.yml` files, excluding `datadog-service-catalog.yml` and empty strings
2. If no files are found, the update job is skipped
3. For each changed file, checks out the pushed commit, reads the YAML content and schema version using `yq`, and POSTs to the Datadog API

The `datadog-service-catalog.yml` master catalog file is intentionally excluded — it is a multi-document YAML file managed separately and does not map 1:1 to individual API calls.

**Required secrets:** `DD_API_KEY`, `DD_APP_KEY`

---

### `datadog_service_catalog_delete.yml` — Delete Datadog service from Datadog

**Trigger:** Push to `master` that modifies any file matching `datadog-service-catalog/**.yml`

When a PR is merged to master and individual service definition files have been deleted, this workflow removes those services from the Datadog Service Catalog via the API. The workflow:

1. Diffs `github.event.before` against `github.event.after` to find deleted `.yml` files, excluding `datadog-service-catalog.yml` and empty strings
2. If no files were deleted, the delete job is skipped
3. For each deleted file, checks out the **pre-merge commit** (`github.event.before`) so the deleted files are still accessible, reads the service name and schema version using `yq`, and sends a DELETE request to the Datadog API

Checking out the pre-merge commit is necessary because the deleted files no longer exist on master after the merge.

**Required secrets:** `DD_API_KEY`, `DD_APP_KEY`

---

### `datadog_service_catalog_warn_delete.yml` — Warn PR if it deletes a Datadog Service Catalog File

**Trigger:** Pull requests (opened, reopened, synchronize) that modify any file matching `datadog-service-catalog/**.yml`

Posts a warning comment on any PR that deletes a service definition file, reminding the author that merging will automatically delete that service from the Datadog Service Catalog. The workflow:

1. Diffs the PR branch against master to find deleted `.yml` files, excluding `datadog-service-catalog.yml`
2. If deleted files are found, checks whether the warning comment has already been posted to avoid duplicates on subsequent pushes to the same PR
3. If not already posted, comments on the PR with a warning message

---

## File Structure

```
datadog-service-catalog/
  datadog-service-catalog.yml   # Master multi-document catalog file (not validated or synced individually)
  <service-name>.yml            # Individual service definition files (validated and synced by workflows)

.github/
  workflows/
    validate-datadog-changes.yml
    validate-datadog-changes-skip.yml
    datadog_service_catalog_update.yml
    datadog_service_catalog_delete.yml
    datadog_service_catalog_warn_delete.yml
  scripts/
    validate-datadog-yaml/
      validate_yaml.py
      datadog-schema2.2.json
      requirements.txt
      README.md                 # This file
```
