# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The maintained `main` branch is now explicitly constrained to one root
  commit, with verified updates published using a leased history replacement.
- `andx-project init` now initializes an independent local Git repository in
  every generated project, verifies the target is Git's top level, and leaves
  remote creation explicit. Generated projects no longer inherit a parent
  checkout as their commit target.

### Added

- `andx-project adopt` for existing repositories: creates missing envelope
  directories and files only, never overwrites or merges, reports each
  conflict with the exact path and a suggested manual resolution, and
  supports `--dry-run` with the complete proposed-change report.
- Durable `.andx-starter` version marker written by both `init` and `adopt`,
  containing no machine-specific data.

## [0.1.0] - 2026-07-24

### Added

- Safe project initializer `andx-project init` creating the stable directory
  envelope with agent-neutral operating rules and thin vendor adapters.
- Continuity skill and `andx-continuity` command with bounded,
  model-independent recovery state, drift checking, memory audit, and factual
  handoffs.
- Schema 2 continuity state with a content-derived drift fingerprint over
  staged, unstaged, and untracked work; legacy or malformed snapshots fail
  closed and never report a match.
- Installer conflict diagnostics describing what occupies a refused
  destination, with an uninstall hint for sibling checkouts.
- ShellCheck lint job in CI alongside the macOS and Ubuntu integration
  matrix.
- `VERSION` marker and `--version` flags on both commands.

### Fixed

- The best-effort continuity hook exits silently for repositories without a
  commit instead of failing loudly.

[0.1.0]: https://github.com/andxblink/andx_lean-agent-starter/releases/tag/v0.1.0
