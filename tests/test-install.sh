#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install.sh"
test_root="$(mktemp -d)"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_not_exists() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"
}

dry_home="$test_root/dry-home"
dry_skill_dir="$dry_home/agent-skills"
mkdir -p "$dry_home"
HOME="$dry_home" \
  bash "$installer" --dry-run --skill-dir "$dry_skill_dir" >/dev/null
assert_not_exists "$dry_home/.local/bin/andx-project"
assert_not_exists "$dry_home/.local/bin/andx-continuity"
assert_not_exists "$dry_skill_dir/continuity"

install_home="$test_root/install-home"
codex_skill_dir="$install_home/codex/skills"
claude_skill_dir="$install_home/claude/skills"
mkdir -p "$install_home"
HOME="$install_home" bash "$installer" \
  --skill-dir "$codex_skill_dir" \
  --skill-dir "$claude_skill_dir" \
  --skill-dir "$codex_skill_dir" >/dev/null
command_target="$install_home/.local/bin/andx-project"
continuity_target="$install_home/.local/bin/andx-continuity"
codex_skill_target="$codex_skill_dir/continuity"
claude_skill_target="$claude_skill_dir/continuity"
[[ -L "$command_target" ]] || fail "command link was not installed"
[[ -L "$continuity_target" ]] ||
  fail "continuity command link was not installed"
[[ -L "$codex_skill_target" ]] || fail "Codex skill link was not installed"
[[ -L "$claude_skill_target" ]] || fail "Claude skill link was not installed"
[[ "$(readlink "$command_target")" == "$repo_root/bin/andx-project" ]] ||
  fail "command link has the wrong source"
[[ "$(readlink "$continuity_target")" == "$repo_root/bin/andx-continuity" ]] ||
  fail "continuity command link has the wrong source"
[[ "$(readlink "$codex_skill_target")" == "$repo_root/skills/continuity" ]] ||
  fail "Codex skill link has the wrong source"
[[ "$(readlink "$claude_skill_target")" == "$repo_root/skills/continuity" ]] ||
  fail "Claude skill link has the wrong source"
HOME="$install_home" bash "$installer" \
  --skill-dir "$codex_skill_dir" \
  --skill-dir "$claude_skill_dir" >/dev/null ||
  fail "install is not idempotent"
"$continuity_target" --help >/dev/null ||
  fail "installed continuity command is not executable"

HOME="$install_home" bash "$installer" --uninstall --dry-run \
  --skill-dir "$codex_skill_dir" \
  --skill-dir "$claude_skill_dir" >/dev/null
[[ -L "$command_target" && -L "$continuity_target" &&
   -L "$codex_skill_target" && -L "$claude_skill_target" ]] ||
  fail "uninstall dry-run changed installed links"
HOME="$install_home" bash "$installer" --uninstall \
  --skill-dir "$codex_skill_dir" \
  --skill-dir "$claude_skill_dir" >/dev/null
assert_not_exists "$command_target"
assert_not_exists "$continuity_target"
assert_not_exists "$codex_skill_target"
assert_not_exists "$claude_skill_target"

partial_home="$test_root/partial-uninstall-home"
partial_skill_dir="$partial_home/agent/skills"
mkdir -p "$partial_home"
HOME="$partial_home" bash "$installer" \
  --skill-dir "$partial_skill_dir" >/dev/null
partial_command_target="$partial_home/.local/bin/andx-project"
partial_continuity_target="$partial_home/.local/bin/andx-continuity"
partial_skill_target="$partial_skill_dir/continuity"
unlink "$partial_command_target"
printf '%s\n' "unrelated replacement" > "$partial_command_target"
HOME="$partial_home" bash "$installer" --uninstall \
  --skill-dir "$partial_skill_dir" >/dev/null 2>&1 ||
  fail "uninstall failed because one destination became unrelated"
[[ -f "$partial_command_target" && ! -L "$partial_command_target" ]] ||
  fail "uninstall changed an unrelated replacement"
assert_not_exists "$partial_continuity_target"
assert_not_exists "$partial_skill_target"

command_conflict_home="$test_root/command-conflict"
command_conflict_skill_dir="$command_conflict_home/skills"
mkdir -p "$command_conflict_home/.local/bin"
printf '%s\n' "unrelated" > \
  "$command_conflict_home/.local/bin/andx-project"
if HOME="$command_conflict_home" \
  bash "$installer" --skill-dir "$command_conflict_skill_dir" \
  >/dev/null 2>&1; then
  fail "installer accepted an unrelated command"
fi
assert_not_exists "$command_conflict_home/.local/bin/andx-continuity"
assert_not_exists "$command_conflict_skill_dir/continuity"

foreign_symlink_home="$test_root/foreign-symlink"
mkdir -p "$foreign_symlink_home/.local/bin"
ln -s "$test_root/somewhere/else" \
  "$foreign_symlink_home/.local/bin/andx-project"
foreign_symlink_status=0
foreign_symlink_output="$(
  HOME="$foreign_symlink_home" bash "$installer" 2>&1
)" || foreign_symlink_status=$?
[[ "$foreign_symlink_status" -ne 0 ]] ||
  fail "installer accepted a foreign symlink destination"
[[ "$foreign_symlink_output" == *"symlink to: $test_root/somewhere/else"* ]] ||
  fail "foreign symlink refusal did not name the symlink target"
[[ "$foreign_symlink_output" != *'another checkout of this tool'* ]] ||
  fail "foreign symlink refusal suggested an uninstall from a non-checkout"

sibling_checkout_home="$test_root/sibling-checkout"
mkdir -p "$sibling_checkout_home/.local/bin"
ln -s "$test_root/other-checkout/bin/andx-project" \
  "$sibling_checkout_home/.local/bin/andx-project"
sibling_checkout_status=0
sibling_checkout_output="$(
  HOME="$sibling_checkout_home" bash "$installer" 2>&1
)" || sibling_checkout_status=$?
[[ "$sibling_checkout_status" -ne 0 ]] ||
  fail "installer accepted a sibling-checkout symlink destination"
[[ "$sibling_checkout_output" == *'another checkout of this tool'* ]] ||
  fail "sibling-checkout refusal did not include the uninstall hint"
[[ "$sibling_checkout_output" == *'--uninstall'* ]] ||
  fail "sibling-checkout refusal did not name the uninstall command"

file_conflict_detail_home="$test_root/file-conflict-detail"
mkdir -p "$file_conflict_detail_home/.local/bin"
printf '%s\n' "unrelated" > \
  "$file_conflict_detail_home/.local/bin/andx-project"
file_conflict_detail_output="$(
  HOME="$file_conflict_detail_home" bash "$installer" 2>&1 || true
)"
[[ "$file_conflict_detail_output" == *'currently a regular file'* ]] ||
  fail "file conflict refusal did not describe the file type"

continuity_conflict_home="$test_root/continuity-conflict"
mkdir -p "$continuity_conflict_home/.local/bin"
printf '%s\n' "unrelated" > \
  "$continuity_conflict_home/.local/bin/andx-continuity"
if HOME="$continuity_conflict_home" bash "$installer" >/dev/null 2>&1; then
  fail "installer accepted an unrelated continuity command"
fi
assert_not_exists "$continuity_conflict_home/.local/bin/andx-project"

skill_conflict_home="$test_root/skill-conflict"
skill_conflict_dir="$skill_conflict_home/agent/skills"
mkdir -p "$skill_conflict_dir/continuity"
printf '%s\n' "unrelated" > "$skill_conflict_dir/continuity/SKILL.md"
if HOME="$skill_conflict_home" bash "$installer" \
  --skill-dir "$skill_conflict_dir" >/dev/null 2>&1; then
  fail "installer accepted an unrelated skill"
fi
assert_not_exists "$skill_conflict_home/.local/bin/andx-project"
assert_not_exists "$skill_conflict_home/.local/bin/andx-continuity"

rollback_home="$test_root/rollback-home"
rollback_skill_dir="$rollback_home/agent/skills"
rollback_skill_target="$rollback_skill_dir/continuity"
rollback_bin="$test_root/rollback-bin"
mkdir -p "$rollback_home" "$rollback_bin"
real_ln="$(command -v ln)"
sed \
  -e "s|__REAL_LN__|$real_ln|g" \
  -e "s|__FAIL_TARGET__|$rollback_skill_target|g" \
  "$repo_root/tests/fixtures/failing-ln.sh" > "$rollback_bin/ln"
chmod +x "$rollback_bin/ln"
if HOME="$rollback_home" PATH="$rollback_bin:$PATH" \
  bash "$installer" --skill-dir "$rollback_skill_dir" \
  >/dev/null 2>&1; then
  fail "installer should fail when a requested skill link cannot be created"
fi
assert_not_exists "$rollback_home/.local/bin/andx-project"
assert_not_exists "$rollback_home/.local/bin/andx-continuity"
assert_not_exists "$rollback_skill_target"

invalid_home="$test_root/invalid-home"
mkdir -p "$invalid_home"
for invalid_skill_dir in relative ./relative /; do
  if HOME="$invalid_home" bash "$installer" \
    --skill-dir "$invalid_skill_dir" >/dev/null 2>&1; then
    fail "installer accepted invalid skill directory: $invalid_skill_dir"
  fi
done
assert_not_exists "$invalid_home/.local/bin/andx-project"
assert_not_exists "$invalid_home/.local/bin/andx-continuity"

damaged_root="$test_root/damaged-root"
damaged_home="$test_root/damaged-home"
damaged_skill_dir="$damaged_home/agent/skills"
mkdir -p \
  "$damaged_root" \
  "$damaged_home/.local/bin" \
  "$damaged_skill_dir"
cp "$installer" "$damaged_root/install.sh"
damaged_root_canonical="$(cd "$damaged_root" && pwd -P)"
ln -s "$damaged_root_canonical/bin/andx-project" \
  "$damaged_home/.local/bin/andx-project"
ln -s "$damaged_root_canonical/bin/andx-continuity" \
  "$damaged_home/.local/bin/andx-continuity"
ln -s "$damaged_root_canonical/skills/continuity" \
  "$damaged_skill_dir/continuity"
HOME="$damaged_home" bash "$damaged_root/install.sh" --uninstall \
  --skill-dir "$damaged_skill_dir" >/dev/null ||
  fail "uninstall required source files from a damaged checkout"
assert_not_exists "$damaged_home/.local/bin/andx-project"
assert_not_exists "$damaged_home/.local/bin/andx-continuity"
assert_not_exists "$damaged_skill_dir/continuity"

missing_root="$test_root/missing-root"
missing_home="$test_root/missing-home"
mkdir -p "$missing_root" "$missing_home"
cp "$installer" "$missing_root/install.sh"
if HOME="$missing_home" bash "$missing_root/install.sh" >/dev/null 2>&1; then
  fail "installer accepted missing sources"
fi
assert_not_exists "$missing_home/.local/bin/andx-project"
assert_not_exists "$missing_home/.local/bin/andx-continuity"

printf 'PASS: installer integration tests\n'
