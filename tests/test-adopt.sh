#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_path="$repo_root/bin/andx-project"
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

assert_envelope() {
  local path="$1"
  local entry

  for entry in docs planning handoffs scripts swarms temp .agent; do
    [[ -d "$path/$entry" ]] ||
      fail "missing envelope directory $entry in $path"
  done
  for entry in README.md AGENTS.md CLAUDE.md GEMINI.md .gitignore \
    .andx-starter; do
    [[ -f "$path/$entry" ]] || fail "missing envelope file $entry in $path"
  done
}

assert_no_stray_temp() {
  if find "$1" -maxdepth 1 -name '.andx-adopt.*' -print -quit | grep -q .; then
    fail "adoption left a staged temporary file in $1"
  fi
}

checksum_tree() {
  (
    cd "$1"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum
  )
}

populated_path="$test_root/populated"
mkdir -p "$populated_path/src" "$populated_path/docs"
printf 'existing readme\n' > "$populated_path/README.md"
printf 'console.log(1)\n' > "$populated_path/src/main.js"
printf 'existing doc\n' > "$populated_path/docs/notes.md"
printf '%s\n' 'node_modules/' '.agent/' 'temp/' > "$populated_path/.gitignore"
populated_before="$(checksum_tree "$populated_path")"
populated_output="$("$command_path" adopt "$populated_path")" ||
  fail "conflict-free populated adoption exited nonzero"
assert_envelope "$populated_path"
assert_no_stray_temp "$populated_path"
[[ "$populated_output" == *'keep   README.md'* ]] ||
  fail "populated adoption did not report the kept README"
[[ "$populated_output" == *'create AGENTS.md'* ]] ||
  fail "populated adoption did not report created files"
[[ ! -e "$populated_path/docs/.gitkeep" ]] ||
  fail "adoption added .gitkeep to a populated durable directory"
[[ "$(head -n 1 "$populated_path/.andx-starter")" == \
  "starter_version=$starter_version" ]] ||
  fail "version marker does not record the starter version"
populated_after="$(checksum_tree "$populated_path")"
while IFS= read -r line; do
  [[ "$populated_after" == *"$line"* ]] ||
    fail "adoption changed a pre-existing byte: $line"
done <<< "$populated_before"

empty_path="$test_root/empty"
mkdir "$empty_path"
"$command_path" adopt "$empty_path" >/dev/null ||
  fail "empty-directory adoption exited nonzero"
assert_envelope "$empty_path"
[[ -f "$empty_path/docs/.gitkeep" ]] ||
  fail "adoption skipped .gitkeep in a created durable directory"

init_path="$test_root/init-project"
"$command_path" init "$init_path" --purpose "Prove envelope parity." >/dev/null
assert_envelope "$init_path"
cmp "$init_path/AGENTS.md" "$empty_path/AGENTS.md" ||
  fail "init and adopt generated different canonical rules"

dry_path="$test_root/dry"
mkdir -p "$dry_path"
printf 'keep me\n' > "$dry_path/README.md"
printf 'node_modules/\n' > "$dry_path/.gitignore"
dry_before="$(checksum_tree "$dry_path")"
dry_listing_before="$(cd "$dry_path" && find . | LC_ALL=C sort)"
dry_status=0
dry_output="$("$command_path" adopt "$dry_path" --dry-run)" || dry_status=$?
[[ "$dry_status" -eq 3 ]] ||
  fail "dry run with conflicts returned status $dry_status; expected 3"
[[ "$dry_output" == *'create docs/'* && "$dry_output" == *'keep   README.md'* ]] ||
  fail "dry run did not print the complete proposed-change report"
[[ "$dry_output" == *'Dry run: no changes made.'* ]] ||
  fail "dry run did not announce that nothing changed"
[[ "$(checksum_tree "$dry_path")" == "$dry_before" ]] ||
  fail "dry run changed file contents"
[[ "$(cd "$dry_path" && find . | LC_ALL=C sort)" == "$dry_listing_before" ]] ||
  fail "dry run created or removed paths"

symlink_target="$test_root/symlink-real"
mkdir "$symlink_target"
ln -s "$symlink_target" "$test_root/symlink-entry"
if "$command_path" adopt "$test_root/symlink-entry" >/dev/null 2>&1; then
  fail "adoption accepted a symlinked target"
fi

entry_symlink_path="$test_root/entry-symlink"
entry_symlink_external="$test_root/entry-symlink-external"
mkdir -p "$entry_symlink_path" "$entry_symlink_external"
ln -s "$entry_symlink_external" "$entry_symlink_path/docs"
entry_symlink_status=0
entry_symlink_output="$("$command_path" adopt "$entry_symlink_path")" ||
  entry_symlink_status=$?
[[ "$entry_symlink_status" -eq 3 ]] ||
  fail "symlinked envelope entry returned status $entry_symlink_status"
[[ "$entry_symlink_output" == *'docs: is a symlink'* ]] ||
  fail "symlinked envelope entry was not reported as a conflict"
[[ -z "$(find "$entry_symlink_external" -mindepth 1 -print -quit)" ]] ||
  fail "adoption wrote through a symlinked envelope entry"

adapter_conflict_path="$test_root/adapter-conflict"
mkdir "$adapter_conflict_path"
printf 'Unrelated adapter content.\n' > "$adapter_conflict_path/CLAUDE.md"
adapter_conflict_status=0
adapter_conflict_output="$("$command_path" adopt "$adapter_conflict_path")" ||
  adapter_conflict_status=$?
[[ "$adapter_conflict_status" -eq 3 ]] ||
  fail "diverged adapter returned status $adapter_conflict_status"
[[ "$adapter_conflict_output" == \
  *'CLAUDE.md: point this adapter at AGENTS.md'* ]] ||
  fail "diverged adapter was not reported with a resolution"
[[ "$(cat "$adapter_conflict_path/CLAUDE.md")" == \
  'Unrelated adapter content.' ]] ||
  fail "adoption modified a diverged adapter"

partial_path="$test_root/partial"
mkdir -p "$partial_path/planning"
printf 'custom rules\n' > "$partial_path/AGENTS.md"
printf 'plan\n' > "$partial_path/planning/001_existing.md"
"$command_path" adopt "$partial_path" >/dev/null ||
  fail "partially adopted destination exited nonzero"
assert_envelope "$partial_path"
[[ "$(cat "$partial_path/AGENTS.md")" == 'custom rules' ]] ||
  fail "adoption replaced existing canonical rules"
[[ ! -e "$partial_path/planning/.gitkeep" ]] ||
  fail "adoption added .gitkeep to a populated planning directory"

concurrent_path="$test_root/concurrent"
mkdir "$concurrent_path"
"$command_path" adopt "$concurrent_path" >/dev/null 2>&1 &
first_pid=$!
"$command_path" adopt "$concurrent_path" >/dev/null 2>&1 &
second_pid=$!
wait "$first_pid" || fail "first concurrent adoption failed"
wait "$second_pid" || fail "second concurrent adoption failed"
assert_envelope "$concurrent_path"
assert_no_stray_temp "$concurrent_path"
cmp "$concurrent_path/CLAUDE.md" "$init_path/CLAUDE.md" ||
  fail "concurrent adoption corrupted a generated adapter"

repeat_before="$(checksum_tree "$populated_path")"
"$command_path" adopt "$populated_path" >/dev/null ||
  fail "repeated adoption of a complete envelope exited nonzero"
[[ "$(checksum_tree "$populated_path")" == "$repeat_before" ]] ||
  fail "repeated adoption changed a byte"

printf 'PASS: adoption integration tests\n'
