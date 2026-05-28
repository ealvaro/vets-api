# CI Cache Behavior

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

When a build runs, BuildKit checks which layers have changed and reuses cached blobs for unchanged layers. If only app code changed, layers 1–4 are pulled from cache and only layer 5 is rebuilt. The stable base layer blobs (created May 5th) are shared across all refs and reused on every build.

---

## New PR

### Fail

**Build job:**
- Cleanup buildkit blobs: runs but nothing to delete (new ref, no previous blobs)
- `cache-from` pulls shared base layer blobs from master ✅
- Writes new buildkit blobs for this PR ref
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: miss on this ref → falls back to master ✅
- Restores shard manifest: miss (new run_id) → generates and saves fresh

**Publish results:**
- Docker image tar: **preserved** (PR failure — kept for reruns without rebuilding)
- Shard manifests: deleted
- Runtime log: not saved (tests failed)

**What remains in cache:** `docker-image-${{ github.sha }}`, buildkit blobs for this PR ref, master runtime log

---

### Success

Same as fail except:

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Runtime log: saved for this PR ref

**What remains in cache:** buildkit blobs for this PR ref, runtime log for this PR ref

---

## New commit to existing PR

### Fail

**Build job:**
- Cleanup buildkit blobs: **deletes previous buildkit blobs for this PR ref** — logs each deleted key and prints a summary e.g. `Done. Deleted: 58, Skipped: 0`
- `cache-from` pulls shared base layer blobs ✅
- Writes fresh buildkit blobs for this commit
- Saves `docker-image-${{ github.sha }}` (new SHA)

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: hits this PR ref from previous successful run (if any) ✅
- Restores shard manifest: miss (new run_id) → generates and saves fresh

**Publish results:**
- Docker image tar: **preserved** (PR failure — kept for reruns without rebuilding)
- Shard manifests: deleted
- Runtime log: not saved

**What remains in cache:** `docker-image-${{ github.sha }}`, fresh buildkit blobs for this PR ref, runtime log

---

### Success

Same as fail except:

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Runtime log: saved, overwriting previous for this PR ref

**What remains in cache:** fresh buildkit blobs for this PR ref, updated runtime log

---

## Master push

### Fail

**Build job:**
- Cleanup buildkit blobs: **skipped** (master — preserves shared stable base layer blobs)
- `cache-from` pulls existing master buildkit blobs ✅
- Writes new buildkit blobs alongside existing ones
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Restores runtime log: hits master ✅
- Restores shard manifest: miss → generates and saves fresh

**Publish results:**
- Docker image tar: **deleted** (master always deletes regardless of outcome)
- Shard manifests: deleted
- Runtime log: not saved

**What remains in cache:** buildkit blobs for master (accumulating), nothing else

---

### Success

Same as fail except:

**Publish results:**
- Docker image tar: deleted
- Shard manifests: deleted
- Runtime log: saved, overwriting previous master runtime log

**What remains in cache:** buildkit blobs for master (accumulating), updated master runtime log

---

## Summary

| Scenario | Docker image tar | Buildkit blobs | Shard manifests | Runtime log |
|---|---|---|---|---|
| New PR fail | Preserved for reruns | Written fresh | Deleted | Not saved |
| New PR success | Deleted | Written fresh | Deleted | Saved |
| Existing PR fail | Preserved for reruns | Previous deleted, fresh written | Deleted | Not saved |
| Existing PR success | Deleted | Previous deleted, fresh written | Deleted | Saved |
| Master fail | Deleted | Accumulate | Deleted | Not saved |
| Master success | Deleted | Accumulate | Deleted | Saved |

## PR close

When a PR is closed (merged or abandoned), the `Cleanup PR Caches` workflow (`.github/workflows/cleanup_pr_caches.yml`) fires and deletes **all** remaining caches for that PR ref in one pass. This covers every cache type that ref could have:

- All `buildkit-blob-*` blobs
- All `index-buildkit-*` entries
- `docker-image-*` tar (if tests failed and it was preserved for reruns)
- Any remaining `shard-manifest-*` entries (if `publish_results` didn't run)
- `parallel-runtime-log-*` for that ref

Nothing is left behind after close. This is the final cleanup that handles anything the per-run cleanup in `publish_results` couldn't reach — primarily the buildkit blobs that accumulated across the PR's lifetime.

## Rerunning a failed test shard

If a single test shard fails, a dev can rerun just that shard without triggering a full rebuild. The `docker-image-${{ github.sha }}` tar is preserved on PR test failures specifically to support this. The shard manifest will regenerate automatically on cache miss if needed. The docker image is only deleted once all tests pass or on a master push.

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

**Delete all caches for a specific ref** — use this to manually nuke a PR or master when the cache limit is being hit:
```bash
gh api --paginate "repos/software/vets-api/actions/caches" --hostname va.ghe.com --jq '.actions_caches[] | select(.ref == "refs/pull/NNNNN/merge") | .id' | while read id; do gh api --hostname va.ghe.com -X DELETE "repos/software/vets-api/actions/caches/$id" --silent || true; done
```

The repo has a hard 10 GB enterprise cache limit. When exceeded, GitHub auto-evicts least-recently-used caches, which can cause `fail-on-cache-miss` failures mid-CI run.