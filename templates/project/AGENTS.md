# AGENTS.md

Project-specific rules in this file extend any inherited agent rules.

## Operating mode

- Work in low-interaction mode by default. Continue through authorized,
  reversible work without asking the user to supervise routine choices.
- Approval prompts are not safety review. Make the command surface safe before
  requesting approval.
- Work directly on the current branch only for small, low-risk, reversible,
  independently verifiable changes when repository policy permits it.
- Use a task branch or worktree for uncertain, multi-step, repeated, or
  cross-system work.

## Delegation

- When the current agent supports delegated workers, treat them as standard
  tools for bounded, independently owned work.
- Delegate when the runtime supports it and parallel execution or fresh-context
  review adds leverage. Do not delegate trivial or tightly serial work.
- Use lower-cost workers for mechanical tasks when practical. Reserve the
  primary agent for judgment, scope, integration, and adversarial review.
- Give workers non-overlapping ownership and concrete output requirements.
- Treat worker summaries as untrusted reports. Inspect artifacts and execute
  checks before accepting their work.
- Only the primary agent updates shared continuity state. Workers return
  artifacts, commit identifiers, executed checks, and unresolved findings.
- Use a verified worker harness when available for repeated batches with
  meaningful executable checks. Prove one representative task before widening
  a batch.

## Knowledge and continuity

- Keep one related objective in the same session through native continuation,
  compaction, or resume when the current agent supports them. Do not rotate
  based on elapsed time or turn count.
- Use the continuity skill or `andx-continuity` command when available for
  compaction checks, lower-model recovery, crashes, or a real session, model,
  operator, repository, or workspace boundary.
- Keep current durable truth in `docs/`.
- Create a file in `planning/` only when coordination, risk, or duration
  justifies a forward plan.
- Keep replaceable active state in ignored `.agent/continuity.md`.
- Create a file in `handoffs/` only when work must cross a real boundary.
- Keep disposable work in `temp/`.
- Add specifications, decision records, specialist loops, or further structure
  only when this project earns them.

## Repository discipline

- Read existing files before writing derivatives.
- Run the narrowest sufficient checks and explain what they prove.
- Stage specific files only. Never use `git add .` or `git add -A`.
- Keep one verified logical change per commit and push when repository rules
  require it.
- Never commit secrets, credentials, token files, `.env`, `temp/`, or
  `.agent/`.

## Stop conditions

Stop rather than guess when the next step requires:

- A product or scope decision reserved for the user.
- Credentials or secret values without an approved path.
- A destructive or difficult-to-reverse action.
- Deployment, publication, spending, or external communication not already
  authorized.
- A broad persistent approval instead of a narrow, bounded command.
