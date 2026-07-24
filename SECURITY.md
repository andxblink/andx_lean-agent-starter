# Security Policy

## Supported versions

Security fixes are applied to the latest released version and the current main
branch.

## Reporting a vulnerability

Do not publish credentials, exploit details, or private repository information
in a public issue.

After this repository is hosted, use its private security-advisory channel to
report vulnerabilities. Until then, contact the repository owner privately.

Include:

- The affected command and version or commit.
- Reproduction steps using disposable paths and placeholder credentials.
- The expected and observed safety boundary.
- Whether files, configuration, or external systems were modified.

## Security boundaries

The installer is allowed to manage only:

```text
~/.local/bin/andx-project
~/.local/bin/andx-continuity
<each explicitly supplied --skill-dir>/continuity
```

It requires absolute skill-directory paths, refuses unrelated destinations,
and never changes global agent configuration, instruction files, hooks,
plugins, project trust, or credentials. The installed symlinks depend on the
checkout remaining at the same path.

Install preflights every destination and rolls back links created during a
failed run. Uninstall removes every verified repository-owned link and skips
unrelated destinations rather than modifying or blocking on them.

The project initializer refuses non-empty and symlink targets. It never reads,
creates, or injects secrets. Its exclusive `mkdir` coordinates concurrent
well-behaved initializers, and it never recursively deletes a claimed target.
Portable Bash cannot make the `mkdir` and following `cd` one atomic operation,
so the initializer is not a security boundary against another process with the
same filesystem authority deliberately replacing that directory between those
two operations.

The ignored continuity snapshot records Git metadata, bounded changed-path
previews, and aggregate drift digests. The digests are derived from repository
content through Git's hasher, but no file contents, diffs, or per-file digests
are persisted or printed, and no Git objects are written. The digests provide
operational drift detection, not cryptographic integrity against an adversary
with the same filesystem authority. Generated committed
handoffs omit absolute repository paths and changed filenames. Manually entered
handoff fields must still be reviewed for private information.
