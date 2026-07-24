# AGENTS.md

These rules apply when contributing to this repository.

## Scope

- Keep the project initializer framework-neutral and zero-dependency.
- Keep the public continuity skill free of personal paths and configuration.
- Keep `AGENTS.md` canonical and agent-neutral. Vendor instruction files may
  only import it or add narrowly vendor-specific guidance.
- Do not add global agent configuration, project trust, plugin state, hooks,
  or machine-specific policy.

## Work discipline

- Read existing behavior and tests before changing it.
- Keep `main` as exactly one root commit. Fold each verified logical change
  into that root commit, then push the replacement immediately with
  `--force-with-lease`. Never publish a second commit on `main`.
- Stage specific files. Never use `git add .` or `git add -A`.
- Update public documentation when behavior changes.
- Preserve macOS system Bash compatibility.

## Verification

- Run `bash tests/run.sh`.
- Run Bash syntax checks for every changed shell script.
- Validate `skills/continuity` with a compatible Agent Skills validator when
  one is available.
- Run `skills/continuity/scripts/continuity-state.sh audit` after changing
  memory rules.

## Safety

- Never commit secrets, credentials, tokens, private keys, personal paths, or
  private repository names.
- The installer may manage only the command and continuity-skill symlinks that
  point to this checkout.
- Never modify global agent configuration, global instruction files, hooks,
  plugins, or project trust.
