# CI Cache Behavior

> Cache cleanup is handled in the `Cleanup run caches` step of the `publish_results` job in `.github/workflows/code_checks.yml`.

This document describes how GitHub Actions caches are used, written, and cleaned up during each `Code Checks` workflow run.

## Cache types

| Cache key pattern | What it is | Size |
|---|---|---|
| `buildkit-blob-1-sha256:*` | Docker image layer blobs written by BuildKit | 0–427 MB each |
| `index-buildkit-1-*` | BuildKit layer index metadata | ~0 MB |
| `docker-image-${{ github.sha }}` | Full compressed Docker image tar (~900 MB) shared across 24 test shards | ~900 MB |
| `parallel-runtime-log-${{ github.ref }}-${{ github.run_id }}` | Per-file rspec runtimes used for shard balancing on next run | ~35 KB |
| `setup-ruby-bundler-cache-*` | Bundled gems for the linting job | ~181 MB |

> **Note:** Shard manifests (`shard-manifest-group-N.txt` + a union manifest) are generated once per
> run by the `shard_manifest` job and shared with all 24 test groups as a **workflow artifact**, not a
> cache. A single artifact can't race with itself the way 24 independent cache restores could, so all
> groups are guaranteed to partition from the same runtime log. Workflow artifacts persist across rerun
> attempts, so rerunning one failed group still executes the exact same file set.

## How BuildKit layer caching works

Docker images are built in layers stacked on top of each other:

1. Base OS (Ubuntu) — never changes
2. Ruby version — rarely changes
3. System packages — rarely changes
4. Gems (bundle install) — changes when Gemfile changes
5. App code — changes on every commit

When a build runs, BuildKit checks which layers have changed and reuses cached blobs for unchanged layers. If only app code changed, layers 1–4 are pulled from cache and only layer 5 is rebuilt.

> **Note:** Buildkit blobs provided no measurable build speedup in practice and were accumulating ~4.8 GB on master alone. They are now deleted after every run for all refs including master.

---

## New PR

### Fail

**Build job:**
- `cache-from: type=gha` attempts to pull buildkit blobs — miss (deleted after previous run)
- Writes new buildkit blobs for this PR ref
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Downloads the `shard-manifests` artifact produced by the `shard_manifest` job

**Publish results:**
- Docker image tar: deleted
- Buildkit blobs: deleted for all refs
- Runtime logs: all PR runtime logs deleted, not saved (tests failed)

**What remains in cache:** latest master runtime log, `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: saved for this PR ref, then deleted on next PR run

**What remains in cache:** runtime log for this PR ref, latest master runtime log, `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

## New commit to existing PR

### Fail

**Build job:**
- `cache-from: type=gha` attempts to pull buildkit blobs — miss (deleted after previous run)
- Writes fresh buildkit blobs for this commit
- Saves `docker-image-${{ github.sha }}` (new SHA)

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Downloads the `shard-manifests` artifact produced by the `shard_manifest` job

**Publish results:**
- Docker image tar: deleted
- Buildkit blobs: deleted for all refs
- Runtime logs: all PR runtime logs deleted, not saved

**What remains in cache:** runtime log from previous successful run (if any), latest master runtime log, `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: saved for this PR ref, then deleted on next PR run

**What remains in cache:** updated runtime log for this PR ref, latest master runtime log, `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

## Master push

### Fail

**Build job:**
- `cache-from: type=gha` attempts to pull buildkit blobs — miss (deleted after previous run)
- Writes new buildkit blobs
- Saves `docker-image-${{ github.sha }}`

**Tests job (×24):**
- Restores `docker-image-${{ github.sha }}` ✅
- Downloads the `shard-manifests` artifact produced by the `shard_manifest` job

**Publish results:**
- Docker image tar: deleted
- Buildkit blobs: deleted for all refs
- Runtime logs: old master runtime logs deleted, not saved (tests failed), latest kept

**What remains in cache:** latest master runtime log (unchanged), `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

### Success

Same as fail except:

**Publish results:**
- Runtime log: new one saved, all previous master runtime logs deleted, only latest kept

**What remains in cache:** updated master runtime log, `setup-ruby-bundler-cache-*`, `codeql-trap-*`

---

## Summary

| Scenario | Docker image tar | Buildkit blobs | Runtime log |
|---|---|---|---|
| New PR fail | Deleted | Written then deleted | Not saved, all PR logs deleted |
| New PR success | Deleted | Written then deleted | Saved, deleted on next PR run |
| Existing PR fail | Deleted | Written then deleted | Not saved, all PR logs deleted |
| Existing PR success | Deleted | Written then deleted | Saved, deleted on next PR run |
| Master fail | Deleted | Written then deleted | Not saved, old logs pruned |
| Master success | Deleted | Written then deleted | Saved, old logs pruned, latest kept |

Shard manifests aren't in this table: they're a workflow artifact produced once by the `shard_manifest`
job, not a cache, so there's nothing to restore, save, or clean up here.

## PR close

When a PR is closed (merged or abandoned), the `Cleanup PR Caches` workflow (`.github/workflows/cleanup_pr_caches.yml`) fires and deletes **all** remaining caches for that PR ref in one pass. In practice, `publish_results` will have already deleted everything for the final run — the close workflow is a safety net for cancelled runs or any edge cases where cleanup didn't fire.

## Rerunning a failed test shard

If a single test shard fails, a dev can rerun just that shard. Since the docker image tar is always deleted after `publish_results`, a rerun will trigger a full rebuild. The shard's manifest comes from the `shard-manifests` artifact produced by the original run's `shard_manifest` job — workflow artifacts persist across rerun attempts, so the rerun executes the exact same file set it did originally.

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

**Delete all parallel runtime logs not accessed in the last 30 minutes** (macOS):
```bash
CUTOFF=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) && \
gh api --paginate "repos/software/vets-api/actions/caches" \
  --hostname va.ghe.com \
  --jq '.actions_caches[]' | \
jq -r --arg cutoff "$CUTOFF" \
  'select(.key | startswith("parallel-runtime-log-")) | select(.last_accessed_at < $cutoff) | .id' | \
while read -r id; do
  gh api --hostname va.ghe.com --silent -X DELETE "repos/software/vets-api/actions/caches/$id" || true
done
```

The repo has a hard 10 GB enterprise cache limit. When exceeded, GitHub auto-evicts least-recently-used caches, which can cause `fail-on-cache-miss` failures mid-CI run.
