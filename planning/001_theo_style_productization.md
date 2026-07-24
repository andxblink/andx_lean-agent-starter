# Plan 001: Lean Agent Starter Productization

Status: Approved direction, implementation not started

## Objective

Turn the current safe project initializer into the fastest credible way to
prepare a new or existing repository for low-interaction, agent-assisted work
without imposing an application stack or formal specification process.

## Fixed product decisions

The complete initial directory envelope remains a feature, not optional
clutter. Every newly initialized project continues to contain:

```text
README.md
AGENTS.md
CLAUDE.md
GEMINI.md
.gitignore
docs/
planning/
handoffs/
scripts/
swarms/
temp/
.agent/
```

Other non-negotiable decisions:

- Keep `AGENTS.md` canonical and agent-neutral.
- Keep the Bash and Git core usable without Node.js or another package runtime.
- Prefer native agent continuation and compaction during a healthy session.
- Keep bounded, model-independent continuity as the recovery layer.
- Keep specifications, specialist loops, and further process optional.
- Preserve low-interaction defaults with explicit authority and safety bounds.
- Treat delegated workers as tools. The primary agent retains judgment,
  integration, verification, and shared-state ownership.
- Do not turn this repository into a GitHub template. It is a generator, and
  generated output must not include the generator's source, tests, or history.

## Product axioms

1. **Start with structure, not methodology.** The stable directory envelope
   makes every project navigable while its application architecture remains
   undecided.
2. **State must survive the agent.** Git and durable repository files are
   authoritative. Conversation memory is replaceable.
3. **Evidence beats status claims.** Completion depends on executed checks and
   inspectable artifacts.

## Phase 1: New and existing repository onboarding

Add a safe brownfield path while preserving the current greenfield behavior.

### Deliverables

- Keep `andx-project init <path>` as the compatibility command.
- Add `andx-project adopt <path>` for an existing repository.
- Add `--dry-run` to both paths with a complete proposed-change report.
- In adoption mode, create missing directories and missing files only.
- Refuse to overwrite or merge existing files automatically.
- Report conflicts with an exact path and a suggested manual resolution.
- Detect the repository's current start and verification commands when they
  can be derived without guessing. Otherwise retain explicit placeholders.
- Record the starter version in a small durable marker that contains no
  machine-specific data.

### Verification

- Tests cover empty, populated, symlinked, concurrent, and partially adopted
  destinations.
- Tests prove adoption never changes an existing byte without an explicit
  future migration operation.
- Tests prove the complete directory envelope exists after both initialization
  and adoption.

## Phase 2: One-command product experience

Keep the zero-dependency core and add a low-friction distribution surface.

### Deliverables

- Choose a public product command that describes the outcome. Recommended:
  `create-agent-repo`.
- Preserve `andx-project` as a documented compatibility alias for at least one
  release.
- Publish a small npm launcher so users can run:

  ```bash
  npx create-agent-repo@latest .
  ```

- Keep direct Bash installation available for users who do not want Node.js.
- Make the first screen explain the result in one sentence.
- Ask only questions that change generated output.
- End with created paths, conflicts, and the exact next command.
- Add `doctor` or `check` to verify the installed project contract.

### Verification

- Run the launcher against a temporary new project and a temporary existing
  repository.
- Verify identical generated content between the npm and direct Bash paths.
- Verify cancellation and failed installation leave no partial global state.

## Phase 3: Public positioning and release

Present the product as a focused generator rather than a universal process.

### Deliverables

- Lead the README with the outcome and one command.
- Position the project as:

  > The fastest way to make any repository ready for coding agents.

- Explain the three product axioms before the detailed architecture.
- Add a 60-second terminal demonstration covering initialization, one agent
  task, verification, and continuity recovery.
- Add GitHub repository topics for discovery.
- Publish a signed or checksummed `v0.1.0` release.
- Add a short comparison page explaining when to choose this starter, a
  spec-driven system, an orchestrator, or only `AGENTS.md`.
- Remove resolved, one-time repository-maintenance snapshots from the active
  public tree before the release. Git history remains the audit trail.

### Verification

- A new user can explain the product and initialize a repository in under two
  minutes without reading the architecture document.
- Every command shown in the README is exercised in CI or a release check.
- The release archive contains no credentials, ignored state, or personal
  filesystem paths.

## Phase 4: Outcome evaluations

Prove the continuity and low-interaction claims rather than relying only on
mechanical shell tests.

### Deliverables

- Create a small, reproducible evaluation corpus with:
  - a compaction-resume task;
  - a fresh-session recovery task;
  - a lower-capability-model recovery task;
  - a dirty-worktree drift task;
  - a delegated-worker integration task.
- Compare native session memory alone with native memory plus bounded
  continuity.
- Measure:
  - correct next-action recovery;
  - repeated work;
  - user interventions;
  - verification completion;
  - state size;
  - approximate token use when the runtime exposes it.
- Separate deterministic CI checks from paid or model-dependent evaluations.
- Publish the method, fixtures, limitations, and raw results.

### Verification

- Another user can reproduce deterministic results locally.
- Model-dependent claims identify the model, runtime, date, sample size, and
  failure cases.
- Marketing language does not generalize beyond the observed results.

## Phase 5: Optional worker contract

Make the existing `swarms/` directory useful without bundling an orchestrator.

### Deliverables

- Define one portable task manifest containing:
  - objective;
  - authority;
  - owned paths;
  - required outputs;
  - required checks;
  - stop conditions.
- Define one result manifest containing:
  - artifacts;
  - commit identifiers when applicable;
  - executed checks and results;
  - unresolved findings;
  - blockers.
- Provide a validator that checks structure and path overlap without calling a
  model.
- Include one cheap-worker example and one independent-review example.
- Keep runtime-specific launchers outside the required core.

### Verification

- Two non-overlapping sample tasks validate and can be integrated by a primary
  agent.
- Conflicting path ownership fails before workers start.
- A worker summary alone can never satisfy completion without the required
  evidence.

## Phase 6: Inspection and upgrade reporting

Support long-lived generated repositories without silently rewriting their
rules.

### Deliverables

- Add `andx-project inspect <path>` to report:
  - starter version;
  - missing envelope paths;
  - adapter drift;
  - continuity health;
  - available migrations.
- Make inspection read-only.
- Add migration commands only for individually specified, reversible changes.
- Require a preview before every migration.
- Never overwrite project-authored `README.md`, `AGENTS.md`, or durable
  knowledge automatically.

### Verification

- Tests cover repositories generated by every released starter version.
- Re-running inspection is idempotent.
- Migration interruption leaves either the old state or a complete new state,
  never an undocumented mixture.

## Delivery order

Implement one verified logical unit per commit:

1. Brownfield adoption and its tests.
2. Read-only project inspection and version marker.
3. Product command naming and compatibility alias.
4. npm launcher with parity tests.
5. README rewrite and terminal demonstration.
6. Repository metadata and `v0.1.0` release preparation.
7. Deterministic evaluation fixtures.
8. Model-dependent evaluation runs and report.
9. Portable worker and result contracts.
10. Migration preview foundation.

Do not begin the next unit until the current unit passes the complete repository
test suite and its public documentation is accurate.

## Explicit non-goals

- No mandatory PRD, specification, architecture, or test methodology.
- No built-in model provider, agent runtime, or desktop interface.
- No semantic personal-memory database.
- No automatic deployment or secret management.
- No simulated company of permanent agent personas.
- No global agent configuration changes.
- No feature added solely because a larger competing harness includes it.

## Success criteria

The product is ready for a stable `1.0` when:

- new and existing repositories are supported safely;
- the complete initial directory envelope remains stable;
- one public command provides a successful first run;
- Codex, Claude, and at least one additional agent can follow the generated
  contract;
- continuity claims have published evidence;
- worker contracts remain optional and runtime-neutral;
- upgrades are inspectable and never silently destructive;
- the public repository contains only durable product material.
