---
name: discover-upstream-services
description: 'Discover and classify upstream service dependencies for the VA Mobile API. Run the discovery script to find unclassified dependencies and propose changes to upstream_services.yml'
argument-hint: 'Optional: full-report (show all dependency chains)'
---

# Discover & Classify Upstream Service Dependencies

## When to Use
- New controllers or services have been added and you want to check for unclassified dependencies
- You want to update `upstream_services.yml` with newly discovered service mappings
- You need an architecture overview of controller→service→upstream dependency chains (use `full-report`)

## Key Files
- **Discovery script:** `modules/mobile/lib/scripts/discover_upstream_chains.rb`
- **Dependency map:** `modules/mobile/lib/scripts/config/upstream_services.yml`
- **Classification prompt:** `modules/mobile/lib/scripts/config/classification_prompt_template.txt`

## Procedure

### 1. Run the discovery script

Execute the discovery script in a terminal and capture the JSON output:

```bash
bundle exec ruby modules/mobile/lib/scripts/discover_upstream_chains.rb
```

The script traces all Mobile controllers (`modules/mobile/app/controllers/**/*.rb`), follows service instantiations through proxies and clients, and classifies them against `upstream_services.yml` using class-prefix matching (i.e., `constant_name.start_with?(prefix)`).

Parse the JSON output into two sections:
- `dependency_chains` — classified upstream dependencies
- `unresolved` — unknown services that could not be classified

### 2. Summarize results

Compute from the `dependency_chains` array:
- Total number of classified service chains
- Number of distinct upstream groups (unique `upstream_service` values)
- Number of unresolved services

Present a single compact summary line:

> **X classified services across Y upstream groups. Z unresolved.**

#### Full report mode

If the user passed `full-report` as an argument, **also** present the full dependency chains as a table before the summary line:

| Feature | Controller | Upstream Service | Call Path |
|---------|-----------|-----------------|-----------|
| Appointments | appointments_controller.rb | VAOS | AppointmentsService → VAOS::Client |

Group rows by feature name. After showing the table and summary, **stop** — do not proceed to classification.

### 3. Check for unresolved services

Inspect the `unresolved` array from the JSON output.

- If empty: report **"All services are classified — no unknown dependencies found."** and **stop**.
- If not empty: list the unresolved services in a table and proceed to step 4.

| Constant | Referenced From | Reason |
|----------|----------------|--------|
| SomeNewService | app/controllers/mobile/v0/... | no matching file found |

### 4. Load classification context

Read these three inputs:

1. **The prompt template** — read `modules/mobile/lib/scripts/config/classification_prompt_template.txt`
2. **Known mappings** — read `modules/mobile/lib/scripts/config/upstream_services.yml`
3. **Unknown services** — the `unresolved` entries from step 1

### 5. Classify unknown services

Build the classification prompt by substituting the template placeholders:

- `{{KNOWN_UPSTREAM_SERVICES}}` → full contents of `upstream_services.yml`
- `{{EXCLUDED_CLASSES}}` → the `excluded_classes` list from the YAML config
- `{{UNKNOWN_SERVICES}}` → the unresolved constants formatted as a list, each with its `constant`, `referenced_from`, and `reason` fields

Then follow the populated prompt instructions to classify each unknown service. Produce exactly two sections as specified by the template:

1. **Proposed additions** — new entries to add to `upstream_services.yml` (under `upstream_groups` and/or `excluded_classes`)
2. **Reasoning** — a markdown table with columns: Mobile Endpoint, Service, Upstream Group, Confidence, Reasoning

### 6. Present results and ask for confirmation

Show both sections from step 5. Then **stop** and ask:

> **Which entries should be added to `upstream_services.yml`?**
>
> Reply with:
> - `all` to apply all proposed additions
> - A comma-separated list of service classes to add selectively (e.g. `NewModule::Service, AnotherClient`)
> - `none` to skip — no changes will be made

Wait for the user's reply before continuing.

### 7. Insert approved entries into upstream_services.yml

For each approved entry, insert it into `modules/mobile/lib/scripts/config/upstream_services.yml`:

- **Upstream entries** go under the `upstream_groups:` section, in alphabetical order by service class name
- **Excluded classes** go under the `excluded_classes:` section

After insertion, read back the file to verify:
- YAML syntax is valid (proper indentation: 2 spaces for keys under `upstream_groups`)
- Alphabetical ordering is maintained
- No duplicate entries

### 8. Verify classification

Re-run the discovery script to confirm the previously unresolved services are now classified:

```bash
bundle exec ruby modules/mobile/lib/scripts/discover_upstream_chains.rb
```

Check the `unresolved` array in the new output:
- If empty: report **"All services are now classified."**
- If still has entries: report remaining unresolved services — these may need manual investigation or new entries in `excluded_classes`
