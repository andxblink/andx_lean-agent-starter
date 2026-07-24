---
name: continuity
description: Keep long-running agent work continuous while maintaining small model-independent recovery state. Use when work may span compaction, session resume, model or agent changes, crashes, long-running goals, lower-capability models, or a real handoff boundary; when the user asks to checkpoint, recover, resume, compact, rotate, hand off, audit memory, or keep context lean; or when context drift must be checked without restarting work.
---

# Continuity

Prefer the current agent's native continuity for one related objective. Keep
the same healthy session, use built-in task or goal tracking when useful, allow
automatic compaction where supported, and resume saved sessions when available.
Never rotate because of elapsed time or turn count.

Use the bundled script for mechanically verified recovery state. Resolve the
script relative to this `SKILL.md`:

```text
scripts/continuity-state.sh
```

## State contract

Treat these sources in descending authority:

1. Current Git state, executed checks, and current durable documentation.
2. The active goal and current plan.
3. `.agent/continuity.md`, which is ignored and replaceable.
4. A committed handoff, which is a boundary snapshot and may be stale.
5. Conversation recall or model-generated compaction summaries.

Never store secrets or source contents in continuity state. The script records
Git metadata, changed paths, and aggregate digests only.

The script enforces a 4,096-byte state limit, 240 characters per work-state
field, and a bounded changed-path preview. Drift is determined by two
fingerprints: a status fingerprint over changed paths and categories, and a
content fingerprint — one aggregate Git-derived digest of the staged diff, the
unstaged tracked diff, and every untracked entry's path, type, and content. A
`MATCH` therefore means the represented repository state, including dirty-file
contents, is unchanged. No file contents or per-file digests are stored.

`check` exits `0` on `MATCH` and `10` on repository-state drift or an obsolete
snapshot schema. A snapshot written by an older schema never reports `MATCH`;
refresh it with the `snapshot` command. A fingerprint failure (for example an
unreadable untracked file) fails closed: the command reports the error, keeps
the previous state, and never silently degrades to a status-only comparison.
Fingerprinting reads a live worktree; a same-authority process writing files
concurrently is detected via bracketing status reads and retried once, not
prevented.

Only the coordinating agent updates shared continuity state. Delegated workers
return artifacts, commit identifiers, executed checks, and unresolved findings.

## Start or resume

1. Prefer the existing saved session. Do not manufacture a handoff merely
   because the terminal restarted.
2. If `.agent/continuity.md` exists, run:

   ```bash
   <skill-dir>/scripts/continuity-state.sh check
   <skill-dir>/scripts/continuity-state.sh show
   ```

3. Compare the snapshot with Git and routed durable sources. Git wins on any
   conflict.
4. If state agrees and the next action is already authorized, continue without
   asking for confirmation.
5. If state differs, determine whether normal work since the snapshot explains
   the drift. Re-orient from Git, tests, the current plan, and current
   documentation. Ask only when a real product or authority decision remains.

## Pulse without stopping

After a meaningful verified unit, before manual compaction, or before a noisy
operation that may obscure active intent, write five short one-line fields:

```bash
<skill-dir>/scripts/continuity-state.sh note \
  --objective "<observable outcome>" \
  --current-unit "<smallest active logical unit>" \
  --last-verified "<check and result, with commit when available>" \
  --next-action "<exact next action>" \
  --blockers "<none, or the exact unresolved condition>" \
  --authority continue
```

Use `--authority ask` only when the next action genuinely needs the user.

This command updates the mechanical snapshot atomically. Continue working. Do
not report a ceremony and do not stop.

For a facts-only refresh that preserves existing work fields:

```bash
<skill-dir>/scripts/continuity-state.sh snapshot --reason logical-unit
```

## Audit memory

After changing `AGENTS.md`, continuity rules, or handoff policy, run:

```bash
<skill-dir>/scripts/continuity-state.sh audit
```

The audit is read-only. It checks the root `AGENTS.md` budget and exact
duplicate instruction bullets, active-state size and Git drift, work-field
limits and placeholders, and handoffs labelled as active truth. Missing active
state is informational. Exit status `0` means no violations; `20` means one or
more violations.

Fix the canonical source and rerun the audit. Do not compensate by loading
every plan, handoff, or document into context.

## Compact

Use agent-native automatic compaction normally when available. Trigger manual
compaction only through the current agent's documented interface and only when
large tool outputs, logs, or discarded exploration pollute the main session.
If the agent cannot compact or resume, pulse before the context boundary and
create a handoff only when another session must take over.

Before an intentional manual compaction, pulse if the five work-state fields
changed. After compaction, run `check`. If it matches, continue. If it does not,
repair orientation from Git and durable sources before acting.

The script also provides a best-effort, silent hook entry point:

```bash
<skill-dir>/scripts/continuity-state.sh hook
```

It writes only when the current directory belongs to a Git repository that
already has an ignored `.agent/` directory and at least one commit. Every
ineligible location exits `0` silently, so the hook never blocks another tool.
Once an eligible snapshot attempt begins, a failure is reported and nonzero.
Hook installation is optional and must not overwrite another tool's hook
configuration.

## Recover

After a crash or unusable session:

1. Resume the saved session when possible.
2. Run `check` and `show`.
3. Inspect `git status`, recent commits, and any referenced verification.
4. Re-run the narrowest check needed to establish current truth.
5. Continue from `Next action` when it remains authorized and consistent.

Do not replay the entire history. Read only the sources required to validate
the active unit.

## Rotate or hand off

Rotate only when work crosses a real boundary:

- a different objective, session, agent, model, operator, repository, or
  workspace;
- an independent clean-room review;
- persistent contradictions after compaction and Git re-orientation;
- an unusable session;
- a formal human-review boundary.

Before promotion, pulse with complete fields. Then run:

```bash
<skill-dir>/scripts/continuity-state.sh handoff two-to-four-word-topic
```

The script refuses incomplete notes, rejects a symlinked `handoffs/` directory,
allocates the next numbered filename, and creates a factual handoff without
committing it. The generated repository-state section omits the absolute
repository path and changed filenames. Review all manually entered fields for
private information, compare the result with Git, add only essential
non-derivable context, stage the exact handoff, commit, and push under
repository policy.

Stop only when the boundary actually requires another session or operator.

## Lower-model discipline

Make `Objective`, `Current unit`, and `Next action` concrete and executable.
Include exact paths or check names when useful. Avoid pronouns whose referent
exists only in the conversation.

Do not ask a lower-capability model to infer:

- the active branch or commit;
- whether the tree changed;
- which verification passed;
- whether the next action is authorized;
- which plan or decision is canonical.

Derive those facts, record them concisely, and verify them on resume.
