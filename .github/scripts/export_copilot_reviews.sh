#!/usr/bin/env bash
# export_copilot_reviews.sh
#
# Exports GitHub Copilot's code-review comments on recent PRs in a repo to a CSV.
# Useful for auditing whether Copilot is commenting correctly / consistently
# (e.g. for VA ticket #108598 "Refine Copilot PR Reviews").
#
# Requirements:
#   - GitHub CLI installed and authenticated against your GHE instance:
#       gh auth login --hostname va.ghe.com
#     (do this once; gh will store a token for that host)
#   - `jq` installed.
#
# Usage:
#   ./export_copilot_reviews.sh <owner/repo> [number_of_PRs] [output.csv] [hostname]
#
# Example (VA's GitHub Enterprise instance):
#   ./export_copilot_reviews.sh some-org/vets-api 1000 copilot_reviews.csv va.ghe.com

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo> [num_prs] [output.csv] [hostname]}"
NUM_PRS="${2:-1000}"
OUT="${3:-copilot_reviews.csv}"
GH_HOSTNAME="${4:-va.ghe.com}"
COPILOT_LOGIN="copilot-pull-request-reviewer[bot]"

export GH_HOST="$GH_HOSTNAME"
GH="gh"

echo "Host: $GH_HOSTNAME (via GH_HOST)"
echo "Repo: $REPO"
echo "Scanning the last $NUM_PRS closed/merged PRs for Copilot reviews..."
echo "pr_number,pr_title,pr_url,review_state,review_submitted_at,comment_path,comment_line,comment_body" > "$OUT"

# Get the most recent PRs (any state) — change --state to "merged" if you only want merged ones
PR_LIST=$($GH pr list --repo "$REPO" --state all --limit "$NUM_PRS" --json number,title,url)

echo "$PR_LIST" | jq -c '.[]' | while read -r pr; do
  PR_NUM=$(echo "$pr" | jq -r '.number')
  PR_TITLE=$(echo "$pr" | jq -r '.title')
  PR_URL=$(echo "$pr" | jq -r '.url')

  echo "  Checking PR #$PR_NUM..."

  # Top-level review summaries (state + body) from Copilot
  $GH api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
    | jq -r --arg login "$COPILOT_LOGIN" \
      '.[] | select(.user.login == $login) | [.state, .submitted_at, (.body // "" | gsub("\n"; " ") | gsub(","; ";"))] | @csv' \
    | while IFS=, read -r STATE SUBMITTED BODY; do
        echo "$PR_NUM,\"$PR_TITLE\",$PR_URL,$STATE,$SUBMITTED,,,${BODY}" >> "$OUT"
      done

  # Inline review comments (specific file/line feedback) from Copilot
  $GH api "repos/$REPO/pulls/$PR_NUM/comments" --paginate \
    | jq -r --arg login "$COPILOT_LOGIN" \
      '.[] | select(.user.login == $login) | [.path, (.line // .original_line // ""), (.body // "" | gsub("\n"; " ") | gsub(","; ";"))] | @csv' \
    | while IFS=, read -r PATH_ LINE BODY; do
        echo "$PR_NUM,\"$PR_TITLE\",$PR_URL,inline_comment,,${PATH_},${LINE},${BODY}" >> "$OUT"
      done
done

echo "Done. Wrote $(wc -l < "$OUT") lines to $OUT"
