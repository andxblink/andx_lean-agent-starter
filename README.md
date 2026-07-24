# andx Lean Agent Starter

A small, framework- and agent-neutral project envelope for agent-assisted
software work.
It combines a safe project initializer with a bounded continuity skill for
long-running sessions, model changes, and lower-capability model recovery.

## Quick start

Use this starter to prepare a new project for coding agents without choosing a
framework or installing application dependencies. You need macOS or Linux,
Bash, and Git.

```bash
git clone https://github.com/andxblink/andx_lean-agent-starter.git
cd andx_lean-agent-starter
./bin/andx-project init ../my-project \
  --purpose "Describe the first useful outcome."
cd ../my-project
```

You now have an independent local Git repository with shared agent
instructions and clear places for documentation, plans, scripts, and temporary
work. Review the generated files, replace the Start and Verify placeholders,
then make the first commit.

Nothing was published. The command does not create a remote, install a
framework, manage secrets, or deploy the project. To prepare a repository that
already contains files, see [Adopt an existing repository](#adopt-an-existing-repository).

```text
my-project/
├── README.md          purpose, start, and verify commands
├── AGENTS.md          canonical agent operating contract
├── CLAUDE.md          one-line adapter pointing at AGENTS.md
├── GEMINI.md          one-line adapter pointing at AGENTS.md
├── .git/              independent local repository boundary
├── .gitignore         ignores .agent/ and temp/
├── .andx-starter      starter version marker
├── docs/              durable project knowledge
├── planning/          forward plans
├── handoffs/          boundary handoffs
├── scripts/           stable, narrow operations
├── swarms/            optional worker manifests and checks
├── temp/              disposable work, ignored
└── .agent/            replaceable agent state, ignored
```

This is an independent project. It is not affiliated with or endorsed by any
agent vendor.

## Why

New repositories need enough structure to be understandable and recoverable,
but not a production process chosen before the project exists.

The starter provides:

- A concise README and canonical, project-specific `AGENTS.md`.
- Thin `CLAUDE.md` and `GEMINI.md` adapters that point to the canonical rules.
- Clear places for durable knowledge, plans, handoffs, scripts, and agent work.
- Low-interaction defaults with explicit safety boundaries.
- Capability-aware delegation to workers and harnesses.
- Capability-aware continuity without scheduled conversation rotation.
- Deterministic, model-independent recovery state.

It does not choose a framework, install dependencies, manage secrets, deploy,
create a remote repository, or publish.

## Requirements

- macOS or Linux
- Bash 3.2 or newer
- Git for continuity snapshots and drift checks

The initializer and continuity command have no third-party dependencies beyond
Bash and Git. Any coding agent can follow the generated Markdown contract.

## Install

Inspect the intended destinations:

```bash
./install.sh --dry-run
```

Install:

```bash
./install.sh
```

By default this creates only two agent-neutral command symlinks:

```text
~/.local/bin/andx-project
~/.local/bin/andx-continuity
```

Keep the checkout at the same filesystem path while these links are installed.
Run uninstall before moving or deleting the checkout.

It never changes agent configuration, global instruction files, plugins,
hooks, project trust, or credentials.

Ensure `~/.local/bin` is on `PATH`, or run `bin/andx-project` directly.

To add automatic discovery for an Agent Skills-compatible tool, pass one or
more absolute skill directories:

```bash
./install.sh --skill-dir "${CODEX_HOME:-$HOME/.codex}/skills"
./install.sh --skill-dir "$HOME/.claude/skills"
```

The installer creates `continuity` inside each selected directory and refuses
unrelated existing destinations. Tool discovery locations can change, so
confirm the directory with the current agent documentation.

If you used the earlier Codex-specific installer, pass its skill directory on
your next install or uninstall so the existing managed link remains explicit.

Uninstall only links managed by this checkout. Pass the same skill directories
to remove optional skill adapters. Unrelated destinations are reported and
left untouched while other managed links are removed:

```bash
./install.sh --uninstall --dry-run
./install.sh --uninstall
./install.sh --uninstall \
  --skill-dir "${CODEX_HOME:-$HOME/.codex}/skills" \
  --skill-dir "$HOME/.claude/skills"
```

## Start a project

```bash
andx-project init ~/projects/my-project \
  --purpose "Describe the first useful outcome."
```

Then:

```bash
cd ~/projects/my-project
```

`init` creates an independent local Git repository inside the target and does
not configure a remote. This boundary prevents Git from walking up to a parent
checkout and treating that repository as the commit target. Review the files
and make the first commit. Replace the explicit “not selected yet” statements
in `Start` and `Verify` when the project gains its first executable path and
canonical check.

The generated tree is:

```text
README.md
AGENTS.md
CLAUDE.md
GEMINI.md
.gitignore
.andx-starter
.git/
docs/
planning/
handoffs/
scripts/
swarms/
temp/
.agent/
```

Durable empty directories contain `.gitkeep`. `temp/` and `.agent/` are local
and ignored. `.andx-starter` records the starter version that generated the
envelope and contains no machine-specific data. `.git/` belongs only to the
generated project. No remote is inherited from or added to the starter.

## Adopt an existing repository

```bash
andx-project adopt ~/projects/existing-repo --dry-run
andx-project adopt ~/projects/existing-repo
```

Adoption brings an existing directory up to the same envelope by creating
missing directories and missing files only. It never overwrites, merges, or
deletes an existing file. Every conflict — a path of the wrong type, an
ignore file without the `.agent/` and `temp/` rules, an adapter that does not
point at `AGENTS.md` — is reported with the exact path and a suggested manual
resolution, and the command exits `3` while everything safe is still created.
`--dry-run` prints the identical proposed-change report without touching
anything. Start and Verify commands are never guessed from the existing code;
generated files keep explicit placeholders.

## Inspect a project

```bash
andx-project inspect ~/projects/existing-repo
```

Inspection is a read-only contract check. It reports the recorded starter
version, missing or wrongly typed envelope paths, whether the thin agent
adapters still point to `AGENTS.md`, continuity audit health, and any available
migrations. It exits `0` when the current contract is healthy and `3` when it
finds actionable issues.
There are no published migrations yet, so inspection reports `none` rather
than rewriting project-authored files.

## Directory contract

| Directory | Purpose |
| --- | --- |
| `docs/` | Current durable project knowledge |
| `planning/` | Forward plans when coordination, risk, or duration justifies one |
| `handoffs/` | State crossing a real session, agent, model, operator, repository, or workspace boundary |
| `scripts/` | Stable, narrow operations with explicit inputs and bounded effects |
| `swarms/` | Optional multi-agent task manifests and executable checks |
| `temp/` | Disposable checks and worktrees |
| `.agent/` | Ignored, replaceable active agent state |

Application directories develop from the project's actual needs.

## Agent adapters

`AGENTS.md` is the only operating contract. Adapters direct agents to it
rather than importing or copying its contents:

| Agent surface | Adapter |
| --- | --- |
| Codex, GitHub Copilot, Cursor, OpenCode, and other `AGENTS.md` readers | `AGENTS.md` directly |
| Claude Code | `CLAUDE.md` pointing to `AGENTS.md` |
| Gemini CLI | `GEMINI.md` pointing to `AGENTS.md` |
| Other agents | Instruct the agent to read `AGENTS.md`, or add a one-line native adapter |

This uses the documented discovery files for
[Claude Code memory](https://code.claude.com/docs/en/memory),
[Gemini CLI context](https://geminicli.com/docs/cli/gemini-md/), and
[GitHub Copilot agent instructions](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions).

## Continuity

Keep one related objective in the same healthy agent session. Use native
continuation, compaction, and resume when available instead of rotating on a
timer or turn count.

The portable continuity skill and the agent-neutral `andx-continuity` command
manage ignored `.agent/continuity.md`. Git, executed checks, and current
durable documentation remain authoritative.

The skill uses the
[open Agent Skills format](https://support.claude.com/en/articles/12512176-what-are-skills);
the command provides the same deterministic behavior when automatic skill
discovery is unavailable.

Audit memory health:

```bash
andx-continuity audit
```

The tool enforces:

- A 4,096-byte active-state limit.
- A 240-character limit per work-state field.
- A bounded changed-path preview.
- Drift checks against branch, commit, Git status, and a content-derived
  fingerprint of staged, unstaged, and untracked work. Changed-path status
  and content drift are detected separately; only aggregate digests are
  stored, never file contents.
- An 8,192-byte root `AGENTS.md` budget.
- Duplicate instruction and misleading active-handoff detection.

Audit returns `0` when healthy and `20` when it finds policy violations.

See [docs/architecture.md](docs/architecture.md) for the complete state model.

## Safety

The initializer:

- Refuses non-empty and symlink targets.
- Creates a local `.git/` boundary in every initialized project and configures
  no remote.
- Stages output in a temporary sibling directory.
- Refuses observed target conflicts and detects pathname replacement after
  entering the claimed directory.
- Renders user-provided purpose text literally.
- Never reads or creates secrets.

The installer refuses unrelated destinations and does not back up or replace
global configuration.

See [SECURITY.md](SECURITY.md) for reporting guidance.

## Verify

```bash
bash -n \
  install.sh \
  bin/andx-continuity \
  bin/andx-project \
  skills/continuity/scripts/continuity-state.sh \
  tests/*.sh \
  tests/fixtures/*.sh

bash tests/run.sh
```

When a compatible Agent Skills validator is available:

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py skills/continuity
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
