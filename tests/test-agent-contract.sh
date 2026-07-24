#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ "$(git -C "$repo_root" rev-list --count HEAD)" -eq 1 ]] ||
  fail "maintained branch must contain exactly one root commit"

for adapter in \
  "$repo_root/CLAUDE.md" \
  "$repo_root/GEMINI.md" \
  "$repo_root/templates/project/CLAUDE.md" \
  "$repo_root/templates/project/GEMINI.md"; do
  [[ "$(wc -l < "$adapter" | tr -d ' ')" -eq 1 ]] ||
    fail "adapter must contain exactly one line: $adapter"
  # shellcheck disable=SC2016  # the backtick span is the literal adapter text
  [[ "$(sed -n '1p' "$adapter")" == \
    'Read and follow `AGENTS.md` as the canonical project instructions.' ]] ||
    fail "adapter must point to AGENTS.md: $adapter"
done

if grep -E 'Codex|Claude|Gemini|Copilot|Cursor|OpenCode' \
  "$repo_root/templates/project/AGENTS.md" >/dev/null; then
  fail "canonical generated rules contain vendor-specific language"
fi

"$repo_root/bin/andx-continuity" --help |
  grep -F 'continuity-state.sh note' >/dev/null ||
  fail "agent-neutral continuity command did not delegate to the state tool"

version_value="$(cat "$repo_root/VERSION")"
[[ "$version_value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "VERSION is not a semantic version: $version_value"
[[ "$("$repo_root/bin/andx-project" --version)" == "$version_value" ]] ||
  fail "andx-project --version does not print the VERSION marker"
[[ "$("$repo_root/bin/andx-continuity" --version)" == "$version_value" ]] ||
  fail "andx-continuity --version does not print the VERSION marker"
grep -F "## [$version_value]" "$repo_root/CHANGELOG.md" >/dev/null ||
  fail "CHANGELOG.md has no entry for version $version_value"

printf 'PASS: agent contract tests\n'
