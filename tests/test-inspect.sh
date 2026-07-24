#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_path="$repo_root/bin/andx-project"
state_script="$repo_root/skills/continuity/scripts/continuity-state.sh"
starter_version="$(head -n 1 "$repo_root/VERSION")"
test_root="$(mktemp -d)"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

checksum_tree() {
  (
    cd "$1"
    find . -path ./.git -prune -o -type f -print0 |
      LC_ALL=C sort -z | xargs -0 cksum
  )
}

inspect_status() {
  local output_file="$1"
  local target="$2"
  local status=0

  "$command_path" inspect "$target" > "$output_file" || status=$?
  printf '%s\n' "$status"
}

healthy_path="$test_root/healthy"
"$command_path" init "$healthy_path" --purpose "Inspect without mutation." >/dev/null
healthy_before="$(checksum_tree "$healthy_path")"
healthy_listing_before="$(cd "$healthy_path" && find . | LC_ALL=C sort)"
healthy_git_before="$(git -C "$healthy_path" status --porcelain=v1 --untracked-files=all)"
healthy_output="$test_root/healthy.out"
[[ "$(inspect_status "$healthy_output" "$healthy_path")" -eq 0 ]] ||
  fail "healthy project inspection exited nonzero"
grep -F "Starter version: $starter_version (current)" "$healthy_output" >/dev/null ||
  fail "inspection did not report the current starter version"
grep -F 'Missing envelope paths: none' "$healthy_output" >/dev/null ||
  fail "healthy inspection reported missing paths"
grep -F 'Envelope type conflicts: none' "$healthy_output" >/dev/null ||
  fail "healthy inspection reported type conflicts"
grep -F 'Adapter drift: none' "$healthy_output" >/dev/null ||
  fail "healthy inspection reported adapter drift"
grep -F 'Continuity health: healthy (no active snapshot)' "$healthy_output" >/dev/null ||
  fail "inspection did not report inactive continuity as healthy"
grep -F 'Available migrations: none' "$healthy_output" >/dev/null ||
  fail "inspection did not report migration availability"
grep -F 'Inspection result: healthy' "$healthy_output" >/dev/null ||
  fail "inspection did not summarize a healthy project"
[[ "$(checksum_tree "$healthy_path")" == "$healthy_before" ]] ||
  fail "inspection changed project file contents"
[[ "$(cd "$healthy_path" && find . | LC_ALL=C sort)" == "$healthy_listing_before" ]] ||
  fail "inspection changed the project tree"
[[ "$(git -C "$healthy_path" status --porcelain=v1 --untracked-files=all)" == \
  "$healthy_git_before" ]] || fail "inspection changed Git status"

repeat_output="$test_root/repeat.out"
[[ "$(inspect_status "$repeat_output" "$healthy_path")" -eq 0 ]] ||
  fail "repeated healthy inspection exited nonzero"
cmp "$healthy_output" "$repeat_output" ||
  fail "repeated inspection did not produce identical output"

# shellcheck disable=SC2016  # the backtick span is literal adapter text
printf '%s\n' \
  'Read and follow `AGENTS.md` as the canonical project instructions.' \
  'Use the vendor-specific sandbox setting for this project.' \
  > "$healthy_path/CLAUDE.md"
custom_adapter_output="$test_root/custom-adapter.out"
[[ "$(inspect_status "$custom_adapter_output" "$healthy_path")" -eq 0 ]] ||
  fail "inspection rejected an adapter that still points to AGENTS.md"

released_path="$test_root/released-v0.1.0"
"$command_path" init "$released_path" >/dev/null
printf 'starter_version=0.1.0\n' > "$released_path/.andx-starter"
released_output="$test_root/released.out"
[[ "$(inspect_status "$released_output" "$released_path")" -eq 0 ]] ||
  fail "inspection rejected the v0.1.0 project contract"
grep -F 'Starter version: 0.1.0' "$released_output" >/dev/null ||
  fail "inspection did not recognize the released v0.1.0 marker"

findings_path="$test_root/findings"
"$command_path" init "$findings_path" >/dev/null
rm "$findings_path/docs/.gitkeep"
rmdir "$findings_path/docs"
rm "$findings_path/GEMINI.md"
printf 'Custom Claude instructions.\n' > "$findings_path/CLAUDE.md"
findings_before="$(checksum_tree "$findings_path")"
findings_output="$test_root/findings.out"
[[ "$(inspect_status "$findings_output" "$findings_path")" -eq 3 ]] ||
  fail "inspection findings did not return status 3"
grep -F '  docs/' "$findings_output" >/dev/null ||
  fail "inspection did not report a missing directory"
grep -F '  GEMINI.md' "$findings_output" >/dev/null ||
  fail "inspection did not report a missing file"
grep -F '  CLAUDE.md: does not point to AGENTS.md' "$findings_output" >/dev/null ||
  fail "inspection did not report adapter drift"
[[ "$(checksum_tree "$findings_path")" == "$findings_before" ]] ||
  fail "inspection changed a project with findings"

type_path="$test_root/type-conflict"
"$command_path" init "$type_path" >/dev/null
rmdir "$type_path/temp"
printf 'not a directory\n' > "$type_path/temp"
type_output="$test_root/type.out"
[[ "$(inspect_status "$type_output" "$type_path")" -eq 3 ]] ||
  fail "wrong envelope type did not return status 3"
grep -F '  temp/: expected a directory' "$type_output" >/dev/null ||
  fail "inspection did not report the wrong envelope type"

malformed_path="$test_root/malformed-marker"
"$command_path" init "$malformed_path" >/dev/null
printf 'unexpected=0.1.0\n' > "$malformed_path/.andx-starter"
malformed_output="$test_root/malformed.out"
[[ "$(inspect_status "$malformed_output" "$malformed_path")" -eq 3 ]] ||
  fail "malformed marker did not return status 3"
grep -F 'Starter version: unknown (missing or malformed .andx-starter)' \
  "$malformed_output" >/dev/null ||
  fail "inspection did not report the malformed version marker"

continuity_path="$test_root/continuity-drift"
"$command_path" init "$continuity_path" >/dev/null
(
  cd "$continuity_path"
  git config user.name "Inspect Test"
  git config user.email "inspect@example.invalid"
  git add .gitignore AGENTS.md README.md CLAUDE.md GEMINI.md .andx-starter \
    docs/.gitkeep planning/.gitkeep handoffs/.gitkeep scripts/.gitkeep \
    swarms/.gitkeep
  git commit -q -m "initial"
  "$state_script" note \
    --objective "Exercise project inspection" \
    --current-unit "Create a healthy continuity snapshot" \
    --last-verified "Initial project commit exists" \
    --next-action "Introduce and detect repository drift" \
    --blockers "None" \
    --authority continue >/dev/null
  printf 'drift\n' >> README.md
)
continuity_before="$(checksum_tree "$continuity_path")"
continuity_output="$test_root/continuity.out"
[[ "$(inspect_status "$continuity_output" "$continuity_path")" -eq 3 ]] ||
  fail "continuity drift did not return status 3"
grep -F 'Continuity health: needs attention (audit exit 20)' \
  "$continuity_output" >/dev/null ||
  fail "inspection did not report continuity audit failure"
grep -F 'VIOLATION continuity-state drift' "$continuity_output" >/dev/null ||
  fail "inspection did not include actionable continuity detail"
[[ "$(checksum_tree "$continuity_path")" == "$continuity_before" ]] ||
  fail "continuity inspection changed project contents"

non_repo_path="$test_root/non-repository"
mkdir "$non_repo_path"
"$command_path" adopt "$non_repo_path" >/dev/null
non_repo_output="$test_root/non-repo.out"
[[ "$(inspect_status "$non_repo_output" "$non_repo_path")" -eq 3 ]] ||
  fail "non-repository continuity state did not return status 3"
grep -F 'Continuity health: unavailable (target is not a Git repository root)' \
  "$non_repo_output" >/dev/null ||
  fail "inspection did not report unavailable continuity"

if "$command_path" inspect "$test_root/missing" >/dev/null 2>&1; then
  fail "inspection accepted a missing target"
fi
if "$command_path" inspect "$healthy_path" --dry-run >/dev/null 2>&1; then
  fail "inspection accepted redundant --dry-run"
fi
if "$command_path" inspect "$healthy_path" --purpose ignored >/dev/null 2>&1; then
  fail "inspection accepted --purpose"
fi
ln -s "$healthy_path" "$test_root/symlink-target"
if "$command_path" inspect "$test_root/symlink-target" >/dev/null 2>&1; then
  fail "inspection accepted a symlinked target"
fi

printf 'PASS: project inspection integration tests\n'
