# Plan 002: Continuity Drift Correctness and Release Hygiene

Status: Approved

Date: 2026-07-24

Source: two independent external evaluations of this repository, cross-checked
against each other and against the code. Both confirmed the same core defect;
this plan merges their remediations. Where the evaluations disagreed, the
fail-closed position was chosen and the reason is recorded.

Brownfield adoption, distribution, and release positioning remain in
`planning/001_theo_style_productization.md` and are outside this plan, except
that the version marker introduced here is a prerequisite for Phase 1 of that
plan.

## Confirmed problem

`andx-continuity check` computes `status_fingerprint` from:

```bash
git status --porcelain=v1 --untracked-files=all
```

That output describes changed paths and status categories, not their contents.
A deterministic false match follows:

1. Modify or create a file.
2. Take a snapshot.
3. Change the same file's contents again without changing its status category.
4. Run `check`.
5. Observe `MATCH`, exit 0.

The same gap applies to staged files re-staged with different content and to
untracked files whose contents change under a stable path. Replacing `cksum`
with a stronger hash over the same status text would not fix this; the
fingerprint input must include the represented content.

This is an orientation gap, not an integrity breach: Git and executed checks
already outrank the snapshot. But a stale `MATCH` can mislead recovery, which
is the one job the tool has.

## Decisions where the evaluations disagreed

1. **Legacy schema 1 snapshots fail closed.** `check` against schema 1 returns
   drift status `10` with a refresh instruction and never prints `MATCH`. The
   alternative (INFO downgrade, compare remaining keys) can reproduce exactly
   the false-`MATCH` failure being fixed. The state file is ignored and
   replaceable; the refresh cost is one command.
2. **No status-only fallback under load.** A fingerprint error or an oversized
   dirty set never silently degrades to the status-only comparison. A `MATCH`
   whose meaning depends on repository size is uninterpretable for a
   recovering agent. Cost stays visible through recorded runtime in the
   large-set regression test instead.

## Unit 1: Schema 2 content fingerprint

### Design

Introduce state schema 2 with separate descriptive and content-derived fields:

```text
schema=2
fingerprint_scope=index-worktree-untracked-v1
status_fingerprint=<compact status digest>
content_fingerprint=<aggregate Git-derived digest>
```

`status_fingerprint` remains for compact diagnostics and changed-path
comparison. `content_fingerprint` carries correctness and represents three
ordered components:

1. The staged diff relative to HEAD.
2. The unstaged tracked diff relative to the index.
3. A deterministic, NUL-safe manifest of untracked paths, file types, and
   content digests.

HEAD stays a separately recorded and compared field.

Use Git as the hashing dependency; no `sha256sum`/`shasum` requirement:

- Tracked state: full binary diffs with external diff drivers and text
  conversion disabled, streamed into `git hash-object --stdin` (never `-w`).
- Untracked state: enumerate with `git ls-files --others --exclude-standard
  -z` in Git's deterministic order; build a NUL-joined stream of each path,
  file type, and a Git blob digest of its content or symlink target; fail
  closed on unreadable or unsupported filesystem entries — never omit an entry
  and then report `MATCH`.
- Combine labeled component digests into one aggregate digest. Store only the
  aggregate. No diffs, per-file digests, or file contents are persisted or
  printed.

The implementation must not use `git hash-object -w`, refresh or rewrite the
real Git index, create repository objects, or materialize contents in
`.agent/`, temp files, logs, or command output. All Git reads run with
`GIT_OPTIONAL_LOCKS=0`.

### Concurrency and failure behavior

Fingerprinting reads a live worktree and is not an atomic boundary against a
same-authority concurrent writer. For operational races:

- Collect the descriptive status immediately before and after content
  fingerprint generation; retry once when they differ; if state still
  changes, fail without replacing the prior continuity file.
- Content changing while status stays identical during capture yields a
  digest of one observed read. Documented as a limitation, not presented as an
  atomic snapshot.
- Every failure preserves the previous valid state and removes temporaries.

### Schema handling

- `snapshot`, `note`, `handoff`, and eligible `hook` calls write schema 2.
- `snapshot` may load work-state notes from schema 1 before replacing it.
- `show` still displays schema 1 state.
- `check` against schema 1 returns `10` with a refresh instruction, never
  `MATCH`.
- `audit` reports schema 1 as a continuity-state violation naming the refresh
  action and returns `20`.
- Missing, duplicate, malformed, or unknown schema/fingerprint fields fail
  closed.

### Verification

Content drift:

- Unstaged file changes content under a stable ` M` status: `check` exits 10.
- Staged file re-staged with different content under stable `M `: exits 10.
- Untracked file changes content under a stable path: exits 10.
- Mixed staged/unstaged/untracked state, unchanged: stable `MATCH`.
- Restoring exactly the represented state: `MATCH`.
- Deletion, addition, symlink-target, and executable-bit changes detected
  where Git represents them.
- Paths with spaces and unusual characters do not corrupt the manifest.

Privacy and bounds:

- A unique secret-like fixture value changes the digest but never appears in
  the state file, handoff, stdout, stderr, or temporary paths.
- No per-file digest is persisted; state stays within 4,096 bytes.
- A large untracked set stays correct; runtime is recorded in test output.

Read-only operation:

- `check` and `audit` do not change `git status`, the real index checksum, or
  `git count-objects` results.
- A failed fingerprint leaves the previous state byte-for-byte intact and no
  temporary file.

Schema handling:

- Schema 1 never produces `MATCH`; refreshing preserves work-state notes and
  writes schema 2; malformed and unknown schemas fail closed; audit returns
  `20` for legacy state and `0` for healthy schema 2.

### Documentation (same commit)

- `README.md`: distinguish changed-path status from content-derived drift.
- `docs/architecture.md`: schema 2 fields, fingerprint scope, privacy,
  legacy behavior, concurrency limitation.
- `SECURITY.md`: aggregate digests derive from content; no content or
  per-file digest persists.
- `skills/continuity/SKILL.md`: interpreting `MATCH`, schema refresh, and
  fingerprint failures.
- Command help: exit `10` means repository-state drift or an obsolete
  snapshot.

No claim of cryptographic integrity or protection against a same-authority
adversary. The goal is reliable operational drift detection.

## Unit 2: Hook eligibility correction

The best-effort `hook` must be silent and non-blocking when a repository is
not yet eligible:

- Exit `0` without output when the repository has no commit.
- Continue skipping non-repositories and repositories without an ignored
  `.agent/` directory.
- Preserve nonzero failure once an eligible snapshot attempt begins and
  fails; document the distinction.

Tests: hook outside Git, in a commitless repository, and without ignored
agent state all exit `0` silently; hook in an eligible repository writes valid
schema 2 state.

## Unit 3: Installer conflict diagnostics

On conflict, `install.sh` currently prints only
`refusing unrelated destination: PATH`. Improve the refusal message in
`preflight_target`:

- Symlink: print its target; when the target ends in `/bin/andx-project` or
  `/bin/andx-continuity`, add a hint that this looks like another checkout of
  this tool and to run `./install.sh --uninstall` from that checkout first.
- Regular file or directory: print the file type.

Refusal behavior itself does not change. No auto-migration.

Tests in `tests/test-install.sh`: foreign-symlink conflict message contains
the symlink target; sibling-checkout conflict message contains the uninstall
hint.

## Unit 4: ShellCheck in CI

Add a `lint` job to `.github/workflows/test.yml` running ShellCheck (ubuntu
runner; preinstalled) over `install.sh`, both `bin/` commands, the continuity
script, and all test scripts. Fix reported findings; where a warning is
intentional, add a targeted `# shellcheck disable=SCxxxx` with a one-line
justification, never a blanket disable.

## Unit 5: Versioning

- Add a root `VERSION` file and a `--version` flag to `andx-project` and
  `andx-continuity` printing it.
- Add `CHANGELOG.md` (Keep a Changelog format).
- Document the state-schema compatibility policy in `docs/architecture.md`:
  the current schema is authoritative; older schemas are reported for refresh,
  never silently accepted (established in Unit 1).

## Release checkpoint

Tag `v0.1.0` after Units 1 through 5 land and CI is green on macOS and Linux.
Brownfield adoption (`andx-project adopt`, plan 001 Phase 1) starts after the
tag so its behavior change is attributable to a release.

## Delivery order

One verified unit per commit, in the order above. Every unit runs:

```bash
bash -n install.sh bin/andx-continuity bin/andx-project \
  skills/continuity/scripts/continuity-state.sh tests/*.sh tests/fixtures/*.sh
bash tests/run.sh
skills/continuity/scripts/continuity-state.sh audit
```

on macOS Bash 3.2 locally, plus the existing CI matrix. Do not commit a
knowingly failing state to `main`.

## Explicitly out of scope

- Replacing the snapshot authority model; the ranking (Git and executed
  checks above the snapshot) stays.
- Auto-migrating installer conflicts.
- Outcome evaluations of continuity effectiveness (tracked in plan 001
  Phase 4).

## Acceptance criteria

- The reproduced same-status content change returns exit `10`.
- Unchanged staged, unstaged, and untracked state returns `MATCH`.
- Schema 1 can never produce an unqualified `MATCH`.
- No source content or per-file digest is persisted or printed.
- State and field budgets remain enforced; `check` and `audit` stay
  read-only.
- The hook is silent for ineligible repositories.
- ShellCheck, Bash 3.2 syntax checks, all integration tests, the continuity
  audit, and CI pass.
- `--version` works and `v0.1.0` is tagged.
