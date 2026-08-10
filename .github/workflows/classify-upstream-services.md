---
description: |
  AI classification of unknown upstream service dependencies in the VA Mobile
  API. Runs on a schedule: a deterministic pre-agent step discovers upstream
  dependencies, and the agent only runs when unresolved services are found.
  Reads source code, classifies each service, prints a full report, and records
  the findings as a draft item on the VA Mobile App Team project board (project
  494) with action items for updating vets-api and the upstream service map in
  va-mobile-app.

on:
  schedule:
    # 1st of every other month at midnight UTC (Jan, Mar, May, Jul, Sep, Nov)
    - cron: '0 0 1 */2 *'
  workflow_dispatch:

permissions:
  contents: read
  issues: read
  pull-requests: read
  copilot-requests: write

imports:
  - copilot-setup-steps.yml

engine:
  id: copilot
  model: claude-haiku-4.5

max-turns: 25

network:
  allowed:
    - defaults
    - ruby
    - github
    - "api.enterprise.githubcopilot.com"

tools:
  bash:
    - "*"
  github:
    toolsets: [default]

steps:
  - name: Run discovery script
    run: |
      bundle exec ruby modules/mobile/lib/scripts/discover_upstream_chains.rb \
        --output /tmp/gh-aw/agent/upstream_chains.json

  - name: Parse results into summary
    run: |
      UNRESOLVED=$(jq '.unresolved | length' /tmp/gh-aw/agent/upstream_chains.json)
      ENDPOINTS=$(jq '.dependency_chains | length' /tmp/gh-aw/agent/upstream_chains.json)
      CHAINS=$(jq '[.dependency_chains[].chains | length] | add' /tmp/gh-aw/agent/upstream_chains.json)

      jq --argjson e "$ENDPOINTS" --argjson c "$CHAINS" --argjson u "$UNRESOLVED" \
        '{endpoints: $e, chains: $c, unresolved_count: $u, unresolved: .unresolved}' \
        /tmp/gh-aw/agent/upstream_chains.json > /tmp/gh-aw/agent/summary.json

  - name: Build classification prompt
    run: |
      KNOWN=$(cat modules/mobile/lib/scripts/config/upstream_services.yml)
      TEMPLATE=$(cat modules/mobile/lib/scripts/config/classification_prompt_template.txt)
      UNKNOWN=$(jq -r '.unresolved[] | "- \(.constant) (from \(.referenced_from)) — \(.reason)"' /tmp/gh-aw/agent/summary.json)
      EXCLUDED=$(grep -A 100 'excluded_classes:' modules/mobile/lib/scripts/config/upstream_services.yml | tail -n +2 | grep '^ *- ' | sed 's/^ *- /- /')

      echo "$TEMPLATE" | \
        awk -v known="$KNOWN" '{gsub(/\{\{KNOWN_UPSTREAM_SERVICES\}\}/, known); print}' | \
        awk -v excluded="$EXCLUDED" '{gsub(/\{\{EXCLUDED_CLASSES\}\}/, excluded); print}' | \
        awk -v unknown="$UNKNOWN" '{gsub(/\{\{UNKNOWN_SERVICES\}\}/, unknown); print}' \
        > /tmp/gh-aw/agent/classification_prompt.txt

jobs:
  notify-failure:
    needs: agent
    if: always() && needs.agent.result == 'failure'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read 
    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@254c19bd240aabef8777f48595e9d2d7b972184b # v6
        with:
          role-to-assume: ${{ vars.AWS_ASSUME_ROLE }}
          aws-region: us-gov-west-1
      - name: Inject Slack bot token from SSM
        uses: software/action-inject-ssm-secrets@47689845c2a46848eb5455078d9261c8dfe5e521 # latest
        with:
          ssm_parameter: /dsva-vagov/vets-api/common/SLACK_MOBILE_BOT_TOKEN
          env_variable_name: SLACK_API_TOKEN
      - name: Send Slack failure notification
        uses: slackapi/slack-github-action@45a88b9581bfab2566dc881e2cd66d334e621e2c # v3.0.3
        with:
          method: chat.postMessage
          token: ${{ env.SLACK_API_TOKEN }}
          payload: |
            {
              "channel": "C0BF0DD12F2",
              "text": "*Upstream Services* - failed to run workflow.\n<${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View run>"
            }

safe-outputs:
  noop:
    report-as-issue: false
  report-failure-as-issue: false
  jobs:
    report-drift:
      description: "Create a draft item on the VA Mobile App Team project board (project 494) for the upstream drift report and notify Slack"
      needs: safe_outputs
      runs-on: ubuntu-latest
      permissions:
        id-token: write
        contents: read
      inputs:
        title:
          description: "Title for the drift project item"
          required: true
          type: string
        body:
          description: "Markdown body (report) for the drift project item"
          required: true
          type: string
      steps:
        - name: Configure AWS Credentials with OIDC
          uses: aws-actions/configure-aws-credentials@d979d5b3a71173a29b74b5b88418bfda9437d885 # v6.1.1
          with:
            aws-region: us-gov-west-1
            role-to-assume: ${{ vars.AWS_ASSUME_ROLE }}
        - name: Inject FLAGSHIP_MOBILE_CLIENT_ID
          uses: software/action-inject-ssm-secrets@47689845c2a46848eb5455078d9261c8dfe5e521 # latest
          with:
            ssm_parameter: /dsva-vagov/va-mobile-app/dev/FLAGSHIP_MOBILE_CLIENT_ID
            env_variable_name: FLAGSHIP_MOBILE_CLIENT_ID
        - name: Inject FLAGSHIP_MOBILE_APP_PRIVATE_KEY
          uses: software/action-inject-ssm-secrets@47689845c2a46848eb5455078d9261c8dfe5e521 # latest
          with:
            ssm_parameter: /dsva-vagov/va-mobile-app/dev/FLAGSHIP_MOBILE_APP_PRIVATE_KEY
            env_variable_name: FLAGSHIP_MOBILE_APP_PRIVATE_KEY
        - name: Inject Slack bot token from SSM
          uses: software/action-inject-ssm-secrets@47689845c2a46848eb5455078d9261c8dfe5e521 # latest
          with:
            ssm_parameter: /dsva-vagov/vets-api/common/SLACK_MOBILE_BOT_TOKEN
            env_variable_name: SLACK_API_TOKEN
        - name: Generate token
          id: generate_token
          uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
          with:
            client-id: ${{ env.FLAGSHIP_MOBILE_CLIENT_ID }}
            private-key: ${{ env.FLAGSHIP_MOBILE_APP_PRIVATE_KEY }}
            owner: software
            repositories: |
              va-mobile-app
              va-mobile-library
              vets-api
        - name: Create draft item on VA Mobile App Team project
          id: create_item
          env:
            GH_TOKEN: ${{ steps.generate_token.outputs.token }}
            GH_HOST: va.ghe.com
          run: |
            # Custom safe-jobs do NOT receive ${{ inputs.* }}; the agent's tool-call
            # values are delivered as JSON in $GH_AW_AGENT_OUTPUT. The item type is the
            # job name with dashes converted to underscores (report-drift -> report_drift).
            ITEM_TITLE=$(jq -r '.items[] | select(.type == "report_drift") | .title' "$GH_AW_AGENT_OUTPUT" | head -n 1)
            ITEM_BODY=$(jq -r 'first(.items[] | select(.type == "report_drift") | .body)' "$GH_AW_AGENT_OUTPUT")
            if [ -z "$ITEM_TITLE" ]; then
              echo "No report_drift item found in agent output. Skipping."
              exit 0
            fi
            # gh project item-create does not return a browsable URL for DRAFT items,
            # so capture the item's GraphQL node id and derive the board-item URL from
            # its fullDatabaseId. These are plain gh CLI/API calls (no AI credits).
            ITEM_NODE_ID=$(gh project item-create 494 --owner software \
              --title "$ITEM_TITLE" --body "$ITEM_BODY" \
              --format json --jq '.id')
            ITEM_UI_ID=$(gh api graphql -F id="$ITEM_NODE_ID" -f query='
              query($id: ID!) {
                node(id: $id) { ... on ProjectV2Item { fullDatabaseId } }
              }' --jq '.data.node.fullDatabaseId // empty')
            PROJECT_URL=$(gh project view 494 --owner software --format json --jq '.url')
            if [ -n "$ITEM_UI_ID" ]; then
              ITEM_URL="${PROJECT_URL}?pane=issue&itemId=${ITEM_UI_ID}"
            else
              ITEM_URL="$PROJECT_URL"
            fi
            echo "item_url=${ITEM_URL}" >> "$GITHUB_OUTPUT"
        - name: Send Slack Notification
          uses: slackapi/slack-github-action@45a88b9581bfab2566dc881e2cd66d334e621e2c # v3.0.3
          with:
            method: chat.postMessage
            token: ${{ env.SLACK_API_TOKEN }}
            payload: |
              {
                "channel": "C0BF0DD12F2",
                "text": "*Upstream Services* - new unresolved dependencies found.\n<${{ steps.create_item.outputs.item_url || format('{0}/orgs/software/projects/494', github.server_url) }}|View Draft Issue>"
              }
---

# Upstream Service Classifier

Classify unresolved upstream service dependencies. Pre-agent steps already
ran the discovery script, parsed results, and assembled the classification
prompt. **Do not re-read `upstream_services.yml` or
`classification_prompt_template.txt` — their contents are already embedded in
`classification_prompt.txt`.**

## Step 0 — Gate on unresolved count

Before doing anything else, read the unresolved count:

```bash
jq '.unresolved_count' /tmp/gh-aw/agent/summary.json
```

**If `unresolved_count` is `0`**, there is nothing to classify. Immediately
call the `noop` safe output with a message like `"No new upstream services
detected — skipping classification."` and **stop**. Do not read any other
files, run `find`, or produce a report.

**If `unresolved_count` is greater than `0`**, continue to Step 1.

## Step 1 — Read pre-computed context

```bash
cat /tmp/gh-aw/agent/summary.json
cat /tmp/gh-aw/agent/classification_prompt.txt
```

`summary.json` contains `endpoints`, `chains`, `unresolved_count`, and the
`unresolved` array. Print: **"X endpoints · Y chains · Z unresolved"** and
list each unresolved service.

`classification_prompt.txt` contains the full classification rules, known
upstream groups, excluded classes, and the unknown services list. Use it as
the source of truth for classification — do not read any other config files.

## Step 2 — Classify each unknown service

For each unresolved constant, locate its source file:
```bash
find . -path "*/snake_case/class_name.rb" -not -path "*/spec/*" -type f
```

Read the source file to determine if the class makes outbound HTTP calls.
If `find` returns no results, classify as `(unable to locate source)` with
confidence `low`. Do not retry with alternative paths.

Apply the classification rules from `classification_prompt.txt` to produce
the Proposed Additions and Reasoning table in the exact format it specifies.

## Step 3 — Print the full report

Print the report to stdout using this structure:

```
═══════════════════════════════════════════════
  UPSTREAM SERVICE DRIFT REPORT
═══════════════════════════════════════════════

Summary: X endpoints · Y chains · Z unresolved

Unresolved Services:
  • ConstantName (from referenced_file) — reason

Proposed Additions:
  (from Step 2)

Reasoning:
  (from Step 2)

═══════════════════════════════════════════════
```

Also save as Markdown and write to the job summary:
```bash
cat /tmp/gh-aw/agent/report.md >> "$GITHUB_STEP_SUMMARY"
```

## Step 4 — Record the drift report on the project board

Call `report_drift` with:
- **`title`**: `"Z unresolved service(s) detected"` where Z is the
  unresolved count from Step 1.
- **`body`**: A Markdown body containing:
  - Summary line: Upstream drift detected for upstream services. Review the AI proposed changes:
  **X endpoints · Y chains · Z unresolved**. 
  - The Reasoning table from Step 2
  - The Proposed Additions from Step 2
  - A checklist of action items:

    ```markdown
    ## Acceptance Criteria

    - [ ] **vets-api**: Review and verify proposed changes. Use the Copilot skill `discover-upstream-services` to automatically apply the changes or manually edit the file `modules/mobile/lib/scripts/config/upstream_services.yml`
    - [ ] **va-mobile-app**: Update the upstream service Mermaid diagram to add the new upstream group(s), connected to the listed mobile endpoint(s)
    ```

  - Note: *"This workflow detects new services only. Removed or replaced
    services require manual review."*

`report_drift` creates a **draft item** on the VA Mobile App Team project board
(project 494) with your title and body, then sends a Slack notification. A team
member can convert the draft item into a full GitHub issue later.

## Hard Rules

1. **Never open a pull request or commit changes.** Do not use `git` commands
   to create branches, commit, or push.
2. **Only record drift via the `report_drift` safe output.** Do not use GitHub
   MCP tools or `gh` CLI to create issues or project items directly.
3. **Follow the classification rules exactly** as written in
   `classification_prompt.txt`. Do not invent new rules.
4. **Always call `report_drift`** after classification is complete — unless
   Step 0 gated on a zero `unresolved_count`, in which case call `noop` and
   stop instead.
5. **Print the full report to stdout.**
6. **Maintain alphabetical ordering** in proposed diff entries.
7. **Do not read `upstream_services.yml` or `classification_prompt_template.txt`
   directly** — their contents are already in `classification_prompt.txt`.
