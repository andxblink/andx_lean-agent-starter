# Architecture

## Minimal project envelope

The initializer creates stable navigation and operating rules without choosing
an application architecture.

```text
README and canonical AGENTS.md
        |
        v
Durable project knowledge and executable checks
        |
        v
Optional plans, handoffs, scripts, and worker manifests
```

Additional process is added only when project evidence justifies it.

## Agent interface

`AGENTS.md` is the small external interface for agent behavior. Vendor files
are adapters at that seam:

```text
                 AGENTS.md
             canonical contract
              /      |      \
      CLAUDE.md   native     GEMINI.md
        pointer   readers      pointer
```

Keep shared behavior out of adapters. Pointers avoid reinjecting the full
contract on tools that discover several instruction filenames simultaneously.
Add an adapter only when a real agent requires a different discovery filename.

## State hierarchy

Treat state in this order:

1. Current Git state, executed checks, and current durable documentation.
2. The active objective and current plan.
3. Ignored `.agent/continuity.md`.
4. A committed boundary handoff, which may be stale.
5. Conversation recall or generated compaction summaries.

Files on disk consume model context only when read. Keep always-loaded
instructions small and route detailed knowledge through explicit paths.

## Capability-aware continuity

Use the current agent's native continuation, compaction, and saved-session
resume for one related objective when those capabilities exist. Fall back to
the continuity command and factual handoffs when they do not. Wall-clock time
and turn count are not rotation signals.

The ignored continuity snapshot contains:

- Mechanically derived repository root, branch, commit, worktree state,
  Git-status fingerprint, and content fingerprint.
- Objective, current logical unit, last verified result, exact next action,
  blockers, and authority.

The state schema is versioned (currently schema 2, fingerprint scope
`index-worktree-untracked-v1`), and the repository version is recorded in the
root `VERSION` marker, printed by `--version` on both commands. The
compatibility policy is strict: readers accept only the current schema; an
older schema is reported for refresh with drift status, and an unknown schema
fails closed. Legacy state is never silently reinterpreted, because the
ignored snapshot is replaceable at the cost of one command. The status fingerprint digests changed paths
and categories for diagnostics. The content fingerprint carries correctness:
one aggregate digest, computed through Git's own hasher, over the staged diff
relative to HEAD, the unstaged tracked diff relative to the index, and a
NUL-safe manifest of untracked paths, types, and content digests. `check`
reports drift when any recorded field differs; a snapshot from an older schema
is reported for refresh and never accepted as a match. Unknown schemas,
malformed fields, and fingerprint failures fail closed without replacing the
previous state.

Fingerprinting reads a live worktree and is not an atomic boundary against a
same-authority concurrent writer: the content capture is bracketed by two
status reads and retried once, then fails. Content changing while the status
stays identical during capture yields a digest of one observed read.

The ignored state stores paths, metadata, and aggregate digests, not source
contents or per-file digests. It limits the complete state to 4,096 bytes and
keeps changed-path previews bounded. A
generated committed handoff omits the absolute repository path and changed
filenames. Its manually entered fields still require a privacy review.

Rotate or create a committed handoff only when work crosses a real session,
agent, model, operator, repository, or workspace boundary.

## Delegation

When supported, use delegated workers for bounded, independently owned work.
Workers return artifacts, commit identifiers, executed checks, and unresolved
findings. The coordinating agent owns integration, judgment, verification, and
shared continuity state.

A worker harness is optional. When used, it should verify worker output through
executed checks rather than trusting summaries.

## Trust boundaries

The public installer manages only repository-owned command symlinks and
optional skill links in directories explicitly selected by the user. It does
not modify:

- agent configuration
- global instruction files
- hooks or plugins
- project trust
- credentials

The adoption command operates inside a non-empty tree, so it follows a
stricter rule than the initializer: it classifies every envelope entry first,
then creates only the missing ones — directories through bare `mkdir` and
files through a hard link from a staged temporary, both of which fail instead
of overwriting when a path appears concurrently. Existing bytes are never
modified; contract violations in kept files are reported as conflicts with a
suggested manual resolution.

The project initializer writes only into a missing or empty destination that it
claims safely. Before releasing that claim, it initializes `.git/` from inside
the claimed directory with repository-directing Git environment variables
removed. It then verifies that Git's top level is the claimed target. The
result is a local commit boundary even when the project is created below an
existing checkout. No remote is configured; remote repository creation and
publishing remain explicit user actions.

If population or Git initialization fails after the claim, the initializer
leaves that destination in place for inspection and never recursively deletes
it. It coordinates well-behaved concurrent initializers, but portable Bash
cannot make target creation and entry atomic against a same-authority process
that deliberately replaces the directory between those operations. This is an
explicit trust boundary, not a claimed sandbox.
