# CI Cache Behavior

> Cache cleanup is handled in the `Cleanup run caches` step of the `publish_results` job in `.github/workflows/code_checks.yml`.

This document describes how GitHub Actions caches are used, written, and cleaned up during each `Code Checks` workflow run.

## Cache types

| Cache key pattern | What it is | Size |
|---|---|---|
| `buildkit-blob-1-sha256:*` | Docker image layer blobs written by BuildKit | 0–427 MB each |
| `index-buildkit-1-*` | BuildKit layer index metadata | ~0 MB |
| `docker-image-${{ github.sha }}` | Full compressed Docker image tar (~900 MB) shared across 24 test shards | ~900 MB |
| `shard-manifest-${{ github.run_id }}-group-N` | List of spec files for each of the 24 test shards | ~0 MB |
| `parallel-runtime-log-${{ github.ref }}-${{ github.run_id }}` | Per-file rspec runtimes used for shard balancing on next run | ~0 MB |
| `setup-ruby-bundler-cache-*` | Bundled gems for the linting job | ~181 MB |

## How BuildKit layer caching works

Docker images are built in layers stacked on top of each other:

1. Base OS (Ubuntu) — never changes
2. Ruby version — rarely changes
3. System packages — rarely changes
4. Gems (bundle install) — changes when Gemfile changes
5. App code — changes on every commit

When a build runs, BuildKit checks which layers have changed and reuses cached blobs for unchanged layers. If only app code changed, layers 1–4 are pulled from cache and only layer 5 is rebuilt. The stable base layer blobs are shared across all refs and reused on every build.

---

## New PR

### Fail

**Build job:**
- `cache-from` pulls shared base layer blobs from master ✅
- Writes new buildkit blobs for this PR ref
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: miss on this ref → falls back to master ✅
- Restores shard manifest: miss (new run_id) → generates and saves fresh

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Buildkit blobs: deleted for all non-master refs
- Runtime log: not saved (tests failed)

**What remains in cache:** master runtime log, master buildkit blobs

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: saved for this PR ref

**What remains in cache:** runtime log for this PR ref

---

## New commit to existing PR

### Fail

**Build job:**
- `cache-from` pulls shared base layer blobs ✅
- Writes fresh buildkit blobs for this commit
- Saves `docker-image-${{ github.sha }}` (new SHA)

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: hits this PR ref from previous successful run (if any) ✅
- Restores shard manifest: miss (new run_id) → generates and saves fresh

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Buildkit blobs: deleted for all non-master refs (including blobs from previous commits on this PR)
- Runtime log: not saved

**What remains in cache:** runtime log from previous successful run (if any)

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: saved, overwriting previous for this PR ref

**What remains in cache:** updated runtime log for this PR ref

---

## Master push

### Fail

**Build job:**
- `cache-from` pulls existing master buildkit blobs ✅
- Writes new buildkit blobs alongside existing ones
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: hits master ✅
- Restores shard manifest: miss → generates and saves fresh

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Buildkit blobs: untouched (master is excluded from bulk delete)
- Runtime log: not saved

**What remains in cache:** buildkit blobs for master (accumulating), nothing else

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: saved, overwriting previous master runtime log

**What remains in cache:** buildkit blobs for master (accumulating), updated master runtime log

---

## Summary

| Scenario | Docker image tar | Buildkit blobs | Shard manifests | Runtime log |
|---|---|---|---|---|
| New PR fail | Deleted | Written then deleted | Deleted | Not saved |
| New PR success | Deleted | Written then deleted | Deleted | Saved |
| Existing PR fail | Deleted | Previous deleted, fresh written then deleted | Deleted | Not saved |
| Existing PR success | Deleted | Previous deleted, fresh written then deleted | Deleted | Saved |
| Master fail | Deleted | Accumulate | Deleted | Not saved |
| Master success | Deleted | Accumulate | Deleted | Saved |

## PR close

When a PR is closed (merged or abandoned), the `Cleanup PR Caches` workflow (`.github/workflows/cleanup_pr_caches.yml`) fires and deletes **all** remaining caches for that PR ref in one pass. In practice, `publish_results` will have already deleted everything for the final run — the close workflow is a safety net for cancelled runs or any edge cases where cleanup didn't fire.

## Rerunning a failed test shard

If a single test shard fails, a dev can rerun just that shard. Since the docker image tar is always deleted after `publish_results`, a rerun will trigger a full rebuild. The shard manifest will regenerate automatically on cache miss.

---

## Cache inspection commands

**Show total cache count and size grouped by ref, sorted largest first.** Use this to quickly spot which PRs are consuming the most cache storage:
```bash
gh api --paginate "repos/software/vets-api/actions/caches" \
  --hostname va.ghe.com \
  --jq '.actions_caches[]' | \
  jq -s 'group_by(.ref) | map({ref: .[0].ref, count: length, size_mb: (map(.size_in_bytes) | add / 1048576 | round)}) | sort_by(-.size_mb)'
```

**Show every individual cache entry with key, ref, size, and timestamps:**
```bash
gh api --paginate "repos/software/vets-api/actions/caches" --hostname va.ghe.com --jq '.actions_caches[] | {key, ref, size_mb: (.size_in_bytes / 1048576 | round), created_at, last_accessed_at}' | jq -s 'sort_by(.ref)'
```

**Show which PRs with cache entries are still open vs closed/merged.** Useful for finding closed PRs that still have stale caches:
```bash
gh api --paginate "repos/software/vets-api/actions/caches" --hostname va.ghe.com --jq '.actions_caches[]' | \
  jq -s 'group_by(.ref) | map({ref: .[0].ref, count: length, size_mb: (map(.size_in_bytes) | add / 1048576 | round)})' | \
  jq -r '.[] | select(.ref | startswith("refs/pull/")) | .ref | capture("refs/pull/(?<n>[0-9]+)/merge").n' | \
  while read pr; do
    state=$(gh api --hostname va.ghe.com "repos/software/vets-api/pulls/$pr" --jq '{number: .number, state: .state, merged: .merged}')
    echo "$state"
  done
```

**Delete all caches for a specific ref** — use this to manually nuke a PR when the cache limit is being hit:
```bash
gh api --paginate "repos/software/vets-api/actions/caches" --hostname va.ghe.com \
  --jq '.actions_caches[] | select(.ref == "refs/pull/NNNNN/merge") | .id' | \
  while read -r id; do
    gh api --hostname va.ghe.com -X DELETE "repos/software/vets-api/actions/caches/$id" --silent || true
  done
```

The repo has a hard 10 GB enterprise cache limit. When exceeded, GitHub auto-evicts least-recently-used caches, which can cause `fail-on-cache-miss` failures mid-CI run.
