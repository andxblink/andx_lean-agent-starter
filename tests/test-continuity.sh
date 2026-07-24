#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_script="$repo_root/skills/continuity/scripts/continuity-state.sh"
test_root="$(mktemp -d)"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  grep -F -- "$expected" "$file_path" >/dev/null ||
    fail "expected '$expected' in $file_path"
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  if grep -F -- "$unexpected" "$file_path" >/dev/null; then
    fail "did not expect '$unexpected' in $file_path"
  fi
}

assert_text_contains() {
  local text="$1"
  local expected="$2"
  [[ "$text" == *"$expected"* ]] ||
    fail "expected '$expected' in command output"
}

init_repo() {
  local path="$1"
  mkdir -p "$path/.agent" "$path/handoffs"
  (
    cd "$path"
    git init -q
    git config user.name "Continuity Test"
    git config user.email "continuity@example.invalid"
    printf '%s\n' '.agent/' > .gitignore
    printf '%s\n' '# Test repository' > README.md
    printf '%s\n' \
      '# Agent rules' \
      '' \
      '- Keep the repository state mechanically verifiable.' \
      '- Preserve unrelated changes during every task.' \
      '- Apply the shared qualification:' \
      '  Use the first distinct continuation.' \
      '- Apply the shared qualification:' \
      '  Use the second distinct continuation.' \
      '' \
      '```text' \
      '- Ignore this repeated fenced example instruction.' \
      '- Ignore this repeated fenced example instruction.' \
      '```' > AGENTS.md
    git add .gitignore AGENTS.md README.md
    git commit -q -m "initial"
  )
}

project_path="$test_root/project"
init_repo "$project_path"

(
  cd "$project_path"
  "$state_script" snapshot --reason initial >/dev/null
)
state_file="$project_path/.agent/continuity.md"
assert_file "$state_file"
assert_contains "$state_file" 'schema=2'
assert_contains "$state_file" 'fingerprint_scope=index-worktree-untracked-v1'
assert_contains "$state_file" 'content_fingerprint='
assert_contains "$state_file" 'reason=initial'
assert_contains "$state_file" 'worktree=clean'
assert_contains "$state_file" '- Objective: TODO'

(
  cd "$project_path"
  "$state_script" check
) | grep -F 'MATCH branch=' >/dev/null ||
  fail "clean snapshot did not match"

# shellcheck disable=SC2016  # the unexpanded $() text is the fixture itself
literal_objective='Preserve literal $(touch should-not-exist) text'
(
  cd "$project_path"
  "$state_script" note \
    --objective "$literal_objective" \
    --current-unit "Exercise deterministic continuity capture" \
    --last-verified "Initial commit exists" \
    --next-action "Modify README.md and detect drift" \
    --blockers "None" \
    --authority continue >/dev/null
)
assert_contains "$state_file" "- Objective: $literal_objective"
[[ ! -e "$project_path/should-not-exist" ]] ||
  fail "note text was executed"

secret_content='content-that-must-not-enter-continuity-state'
printf '%s\n' "$secret_content" >> "$project_path/README.md"
if (
  cd "$project_path"
  "$state_script" check >/dev/null
); then
  fail "worktree drift was not detected"
else
  check_status=$?
  [[ "$check_status" -eq 10 ]] ||
    fail "drift returned unexpected status $check_status"
fi
assert_not_contains "$state_file" "$secret_content"

(
  cd "$project_path"
  "$state_script" snapshot --reason dirty-tree >/dev/null
  "$state_script" check >/dev/null
)
assert_contains "$state_file" 'worktree=dirty'
assert_contains "$state_file" ' M README.md'
assert_contains "$state_file" "- Objective: $literal_objective"

state_checksum_before="$(cksum < "$state_file")"
long_field="$(printf '%0241d' 0 | tr '0' 'x')"
if (
  cd "$project_path"
  "$state_script" note \
    --objective "$long_field" \
    --current-unit "Exercise field budget" \
    --last-verified "Existing checks passed" \
    --next-action "Reject oversized objective" \
    --blockers "None" >/dev/null 2>&1
); then
  fail "note accepted a work-state field longer than 240 characters"
fi
[[ "$(cksum < "$state_file")" == "$state_checksum_before" ]] ||
  fail "rejected note changed the existing continuity state"

(
  cd "$project_path"
  git checkout -q -b alternate
)
if (
  cd "$project_path"
  "$state_script" check >/dev/null
); then
  fail "branch drift was not detected"
else
  check_status=$?
  [[ "$check_status" -eq 10 ]] ||
    fail "branch drift returned unexpected status $check_status"
fi

(
  cd "$project_path"
  "$state_script" snapshot --reason alternate-branch >/dev/null
  first_handoff="$("$state_script" handoff continuity-checkpoint)"
  second_handoff="$("$state_script" handoff model-boundary)"
  [[ "$(basename "$first_handoff")" == 001-handoff-continuity-checkpoint-*.md ]] ||
    fail "unexpected first handoff name: $first_handoff"
  [[ "$(basename "$second_handoff")" == 002-handoff-model-boundary-*.md ]] ||
    fail "unexpected second handoff name: $second_handoff"
)
assert_file "$(find "$project_path/handoffs" -name '001-handoff-continuity-checkpoint-*.md' -print -quit)"
assert_file "$(find "$project_path/handoffs" -name '002-handoff-model-boundary-*.md' -print -quit)"
assert_contains \
  "$(find "$project_path/handoffs" -name '001-handoff-continuity-checkpoint-*.md' -print -quit)" \
  '## Resume contract'

incomplete_path="$test_root/incomplete"
init_repo "$incomplete_path"
(
  cd "$incomplete_path"
  "$state_script" snapshot >/dev/null
)
if (
  cd "$incomplete_path"
  "$state_script" handoff incomplete-state >/dev/null 2>&1
); then
  fail "handoff accepted incomplete work state"
fi

unsafe_path="$test_root/unsafe"
mkdir -p "$unsafe_path"
(
  cd "$unsafe_path"
  git init -q
  git config user.name "Continuity Test"
  git config user.email "continuity@example.invalid"
  printf '%s\n' '# Unsafe repository' > README.md
  git add README.md
  git commit -q -m "initial"
)
if (
  cd "$unsafe_path"
  "$state_script" snapshot >/dev/null 2>&1
); then
  fail "snapshot wrote unignored agent state"
fi
[[ ! -e "$unsafe_path/.agent/continuity.md" ]] ||
  fail "unsafe snapshot created continuity state"

assert_hook_silent_noop() {
  local hook_path="$1"
  local label="$2"
  local hook_output

  hook_output="$(
    cd "$hook_path"
    "$state_script" hook 2>&1
  )" || fail "$label hook exited nonzero"
  [[ -z "$hook_output" ]] || fail "$label hook produced output: $hook_output"
  [[ ! -e "$hook_path/.agent/continuity.md" ]] ||
    fail "$label hook wrote continuity state"
}

hook_skip_path="$test_root/hook-skip"
mkdir -p "$hook_skip_path"
assert_hook_silent_noop "$hook_skip_path" "outside-git"

hook_commitless_path="$test_root/hook-commitless"
mkdir -p "$hook_commitless_path/.agent"
(
  cd "$hook_commitless_path"
  git init -q
  printf '%s\n' '.agent/' > .gitignore
)
assert_hook_silent_noop "$hook_commitless_path" "commitless-repository"

hook_unignored_path="$test_root/hook-unignored"
mkdir -p "$hook_unignored_path/.agent"
(
  cd "$hook_unignored_path"
  git init -q
  git config user.name "Continuity Test"
  git config user.email "continuity@example.invalid"
  printf '%s\n' '# No ignore rule' > README.md
  git add README.md
  git commit -q -m "initial"
)
assert_hook_silent_noop "$hook_unignored_path" "unignored-agent-state"

hook_eligible_path="$test_root/hook-eligible"
init_repo "$hook_eligible_path"
hook_eligible_output="$(
  cd "$hook_eligible_path"
  "$state_script" hook 2>&1
)" || fail "eligible hook exited nonzero"
[[ -z "$hook_eligible_output" ]] ||
  fail "eligible hook produced output: $hook_eligible_output"
hook_eligible_state="$hook_eligible_path/.agent/continuity.md"
assert_file "$hook_eligible_state"
assert_contains "$hook_eligible_state" 'schema=2'
assert_contains "$hook_eligible_state" 'reason=pre-compact'
assert_contains "$hook_eligible_state" 'content_fingerprint='

budget_path="$test_root/budget"
init_repo "$budget_path"
(
  cd "$budget_path"
  number=1
  while [[ "$number" -le 30 ]]; do
    suffix="$(printf '%0140d' "$number")"
    touch "untracked-$(printf '%02d' "$number")-$suffix"
    number=$((number + 1))
  done
  "$state_script" note \
    --objective "Bound continuity state" \
    --current-unit "Summarize a large changed-path set" \
    --last-verified "Thirty untracked files exist" \
    --next-action "Inspect the bounded snapshot" \
    --blockers "None" >/dev/null
)
budget_state="$budget_path/.agent/continuity.md"
[[ "$(wc -c < "$budget_state" | tr -d ' ')" -le 4096 ]] ||
  fail "continuity state exceeded 4096 bytes"
assert_contains "$budget_state" 'showing 12 of 30 changed paths'
assert_contains "$budget_state" '...'
assert_contains "$budget_state" 'untracked-12-'
assert_not_contains "$budget_state" 'untracked-13-'
budget_check_start="$(date +%s)"
(
  cd "$budget_path"
  "$state_script" check >/dev/null
) || fail "bounded changed-path preview weakened exact drift matching"
printf 'INFO large-untracked-set check runtime seconds=%s\n' \
  "$(( $(date +%s) - budget_check_start ))"
budget_handoff="$(
  cd "$budget_path"
  "$state_script" handoff lean-memory
)"
# shellcheck disable=SC2016  # backtick spans are literal Markdown under test
assert_contains "$budget_handoff" '- Changed path count: `30`'
assert_contains "$budget_handoff" '- Content fingerprint: `'
assert_not_contains "$budget_handoff" "$budget_path"
assert_not_contains "$budget_handoff" 'untracked-01-'

symlink_handoff_path="$test_root/symlink-handoff"
symlink_handoff_external="$test_root/symlink-handoff-external"
init_repo "$symlink_handoff_path"
rmdir "$symlink_handoff_path/handoffs"
mkdir "$symlink_handoff_external"
ln -s "$symlink_handoff_external" "$symlink_handoff_path/handoffs"
(
  cd "$symlink_handoff_path"
  "$state_script" note \
    --objective "Reject an external handoff destination" \
    --current-unit "Exercise the handoff directory boundary" \
    --last-verified "The repository has an initial commit" \
    --next-action "Attempt a handoff through the symlink" \
    --blockers "None" >/dev/null
)
if (
  cd "$symlink_handoff_path"
  "$state_script" handoff symlink-boundary >/dev/null 2>&1
); then
  fail "handoff accepted a symlinked handoff directory"
fi
[[ -z "$(find "$symlink_handoff_external" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  fail "handoff wrote through a symlinked handoff directory"

overflow_path="$test_root/overflow"
max_field="$(printf '%0240d' 0 | tr '0' 'x')"
segment_number=1
while [[ "$segment_number" -le 8 ]]; do
  overflow_path="$overflow_path/$(printf '%060d' "$segment_number")"
  segment_number=$((segment_number + 1))
done
init_repo "$overflow_path"
(
  cd "$overflow_path"
  "$state_script" note \
    --objective "$max_field" \
    --current-unit "$max_field" \
    --last-verified "$max_field" \
    --next-action "$max_field" \
    --blockers "$max_field" >/dev/null
)
overflow_state="$overflow_path/.agent/continuity.md"
overflow_checksum_before="$(cksum < "$overflow_state")"
long_branch_segment="$(printf '%0100d' 0)"
long_branch="$long_branch_segment/$long_branch_segment/$long_branch_segment/$long_branch_segment"
(
  cd "$overflow_path"
  git checkout -q -b "$long_branch"
  number=1
  while [[ "$number" -le 12 ]]; do
    touch "changed-$(printf '%03d' "$number")-$(printf '%0105d' "$number")"
    number=$((number + 1))
  done
)
if (
  cd "$overflow_path"
  "$state_script" snapshot --reason "$max_field" >/dev/null 2>&1
); then
  fail "snapshot accepted generated state larger than 4096 bytes"
fi
[[ "$(cksum < "$overflow_state")" == "$overflow_checksum_before" ]] ||
  fail "oversized generated state replaced the previous snapshot"
if find "$overflow_path/.agent" -name '.continuity.*' -print -quit |
  grep -q .; then
  fail "oversized generated state left a temporary file"
fi

audit_clean_path="$test_root/audit-clean"
init_repo "$audit_clean_path"
(
  cd "$audit_clean_path"
  "$state_script" note \
    --objective "Audit continuity memory" \
    --current-unit "Verify read-only behavior" \
    --last-verified "Initial commit exists" \
    --next-action "Run the memory audit" \
    --blockers "None" >/dev/null
  touch README.md
)
audit_clean_before="$(git -C "$audit_clean_path" status --porcelain=v1 --untracked-files=all)"
audit_clean_index_before="$(cksum < "$audit_clean_path/.git/index")"
audit_clean_output="$(
  cd "$audit_clean_path"
  "$state_script" audit
)"
assert_text_contains "$audit_clean_output" 'PASS agents-size'
assert_text_contains "$audit_clean_output" 'PASS duplicate-instructions'
assert_text_contains "$audit_clean_output" 'PASS continuity-state match'
assert_text_contains "$audit_clean_output" 'PASS handoff-status'
[[ "$(git -C "$audit_clean_path" status --porcelain=v1 --untracked-files=all)" == "$audit_clean_before" ]] ||
  fail "clean audit modified repository state"
[[ "$(cksum < "$audit_clean_path/.git/index")" == "$audit_clean_index_before" ]] ||
  fail "clean audit refreshed the Git index"

audit_incomplete_path="$test_root/audit-incomplete"
init_repo "$audit_incomplete_path"
(
  cd "$audit_incomplete_path"
  "$state_script" snapshot >/dev/null
)
if audit_incomplete_output="$(
  cd "$audit_incomplete_path"
  "$state_script" audit 2>&1
)"; then
  fail "audit accepted placeholder continuity fields"
else
  audit_status=$?
  [[ "$audit_status" -eq 20 ]] ||
    fail "incomplete audit returned unexpected status $audit_status"
fi
assert_text_contains "$audit_incomplete_output" \
  'VIOLATION continuity-state field-placeholder=Objective'

audit_duplicate_state_path="$test_root/audit-duplicate-state"
init_repo "$audit_duplicate_state_path"
(
  cd "$audit_duplicate_state_path"
  "$state_script" note \
    --objective "Audit duplicate state fields" \
    --current-unit "Validate state schema cardinality" \
    --last-verified "Initial commit exists" \
    --next-action "Run the memory audit" \
    --blockers "None" >/dev/null
)
printf '%s\n' "- Objective: $long_field" >> \
  "$audit_duplicate_state_path/.agent/continuity.md"
if audit_duplicate_state_output="$(
  cd "$audit_duplicate_state_path"
  "$state_script" audit 2>&1
)"; then
  fail "audit accepted duplicate continuity fields"
else
  audit_status=$?
  [[ "$audit_status" -eq 20 ]] ||
    fail "duplicate-state audit returned unexpected status $audit_status"
fi
assert_text_contains "$audit_duplicate_state_output" \
  'VIOLATION continuity-state field-count=Objective count=2 expected=1'

audit_stale_path="$test_root/audit-stale"
init_repo "$audit_stale_path"
(
  cd "$audit_stale_path"
  "$state_script" snapshot >/dev/null
  printf '%s\n' 'drift' >> README.md
)
if audit_stale_output="$(
  cd "$audit_stale_path"
  "$state_script" audit 2>&1
)"; then
  fail "audit accepted stale continuity state"
else
  audit_status=$?
  [[ "$audit_status" -eq 20 ]] ||
    fail "stale audit returned unexpected status $audit_status"
fi
assert_text_contains "$audit_stale_output" 'VIOLATION continuity-state drift'

audit_agents_path="$test_root/audit-agents"
init_repo "$audit_agents_path"
{
  printf '%s\n' \
    '- Repeat:' \
    '  Preserve this complete multiline instruction for audit detection.' \
    '- Repeat:' \
    '  Preserve this complete multiline instruction for audit detection.'
  printf '%09000d\n' 0
} >> "$audit_agents_path/AGENTS.md"
if audit_agents_output="$(
  cd "$audit_agents_path"
  "$state_script" audit 2>&1
)"; then
  fail "audit accepted oversized AGENTS.md with duplicate instructions"
else
  audit_status=$?
  [[ "$audit_status" -eq 20 ]] ||
    fail "agents audit returned unexpected status $audit_status"
fi
assert_text_contains "$audit_agents_output" 'VIOLATION agents-size'
assert_text_contains "$audit_agents_output" 'VIOLATION duplicate-instruction'

audit_handoff_path="$test_root/audit-handoff"
init_repo "$audit_handoff_path"
mkdir -p "$audit_handoff_path/handoffs"
printf '%s\n' \
  '# Handoff: stale current state' \
  '' \
  'Status: In PrOgReSs   ' > "$audit_handoff_path/handoffs/001-handoff-stale-current-2026-07-24.md"
(
  cd "$audit_handoff_path"
  git add handoffs/001-handoff-stale-current-2026-07-24.md
  git commit -q -m "add incorrectly active handoff"
)
if audit_handoff_output="$(
  cd "$audit_handoff_path"
  "$state_script" audit 2>&1
)"; then
  fail "audit accepted a handoff labelled as active truth"
else
  audit_status=$?
  [[ "$audit_status" -eq 20 ]] ||
    fail "handoff audit returned unexpected status $audit_status"
fi
assert_text_contains "$audit_handoff_output" 'VIOLATION handoff-status'

expect_check_status() {
  local repo_path="$1"
  local expected="$2"
  local label="$3"
  local observed=0

  (
    cd "$repo_path"
    "$state_script" check >/dev/null 2>&1
  ) || observed=$?
  [[ "$observed" -eq "$expected" ]] ||
    fail "$label returned status $observed; expected $expected"
}

content_path="$test_root/content-drift"
init_repo "$content_path"
(
  cd "$content_path"
  printf 'dirty-one\n' >> README.md
  printf 'untracked-one\n' > notes.txt
  printf 'staged-one\n' > staged.txt
  printf 'spaced-one\n' > 'file with spaces.txt'
  git add staged.txt
  "$state_script" snapshot --reason content-baseline >/dev/null
)
content_state="$content_path/.agent/continuity.md"
content_objects_before="$(git -C "$content_path" count-objects)"
expect_check_status "$content_path" 0 "mixed dirty baseline"
expect_check_status "$content_path" 0 "repeated unchanged check"
[[ "$(git -C "$content_path" count-objects)" == "$content_objects_before" ]] ||
  fail "content fingerprint check created Git objects"

cp "$content_path/README.md" "$test_root/readme.baseline"
printf 'dirty-two\n' >> "$content_path/README.md"
expect_check_status "$content_path" 10 \
  "unstaged content change under a stable status"
cp "$test_root/readme.baseline" "$content_path/README.md"
expect_check_status "$content_path" 0 "exactly restored unstaged content"

printf 'untracked-two\n' > "$content_path/notes.txt"
expect_check_status "$content_path" 10 \
  "untracked content change under a stable path"
(
  cd "$content_path"
  "$state_script" snapshot --reason untracked-baseline >/dev/null
)

printf 'staged-two\n' > "$content_path/staged.txt"
git -C "$content_path" add staged.txt
expect_check_status "$content_path" 10 \
  "re-staged content change under a stable status"
(
  cd "$content_path"
  "$state_script" snapshot --reason staged-baseline >/dev/null
)

printf 'spaced-two\n' > "$content_path/file with spaces.txt"
expect_check_status "$content_path" 10 \
  "content change in a path containing spaces"
(
  cd "$content_path"
  "$state_script" snapshot --reason spaces-baseline >/dev/null
)

chmod +x "$content_path/notes.txt"
expect_check_status "$content_path" 10 \
  "untracked executable-bit change"
(
  cd "$content_path"
  ln -s notes.txt retarget-link
  "$state_script" snapshot --reason symlink-baseline >/dev/null
  rm retarget-link
  ln -s staged.txt retarget-link
)
expect_check_status "$content_path" 10 "untracked symlink-target change"

secret_check_content="fingerprint-secret-$(date +%s)-must-stay-out"
printf '%s\n' "$secret_check_content" >> "$content_path/README.md"
secret_check_output="$(
  cd "$content_path"
  "$state_script" check 2>&1 || true
)"
[[ "$secret_check_output" != *"$secret_check_content"* ]] ||
  fail "check output leaked dirty file content"
(
  cd "$content_path"
  "$state_script" snapshot --reason secret-baseline >/dev/null
)
assert_not_contains "$content_state" "$secret_check_content"

legacy_path="$test_root/schema-legacy"
init_repo "$legacy_path"
(
  cd "$legacy_path"
  "$state_script" note \
    --objective "Preserve notes across a schema refresh" \
    --current-unit "Exercise legacy schema handling" \
    --last-verified "Initial commit exists" \
    --next-action "Refresh the legacy snapshot" \
    --blockers "None" >/dev/null
)
legacy_state="$legacy_path/.agent/continuity.md"
sed \
  -e 's/^schema=2$/schema=1/' \
  -e '/^fingerprint_scope=/d' \
  -e '/^content_fingerprint=/d' \
  "$legacy_state" > "$legacy_state.tmp"
mv "$legacy_state.tmp" "$legacy_state"
legacy_output="$(
  cd "$legacy_path"
  "$state_script" check 2>&1 || true
)"
expect_check_status "$legacy_path" 10 "legacy schema 1 snapshot"
[[ "$legacy_output" == *'DRIFT schema recorded=1'* ]] ||
  fail "legacy schema check did not name the schema drift"
[[ "$legacy_output" != *'MATCH'* ]] ||
  fail "legacy schema check printed MATCH"
if (
  cd "$legacy_path"
  "$state_script" audit >/dev/null 2>&1
); then
  fail "audit accepted a legacy schema snapshot"
fi
(
  cd "$legacy_path"
  "$state_script" snapshot --reason schema-refresh >/dev/null
)
assert_contains "$legacy_state" 'schema=2'
assert_contains "$legacy_state" \
  '- Objective: Preserve notes across a schema refresh'
expect_check_status "$legacy_path" 0 "refreshed legacy snapshot"

unknown_schema_path="$test_root/schema-unknown"
init_repo "$unknown_schema_path"
(
  cd "$unknown_schema_path"
  "$state_script" snapshot >/dev/null
)
unknown_state="$unknown_schema_path/.agent/continuity.md"
sed 's/^schema=2$/schema=3/' "$unknown_state" > "$unknown_state.tmp"
mv "$unknown_state.tmp" "$unknown_state"
unknown_status=0
unknown_output="$(
  cd "$unknown_schema_path"
  "$state_script" check 2>&1
)" || unknown_status=$?
[[ "$unknown_status" -ne 0 && "$unknown_status" -ne 10 ]] ||
  fail "unknown schema did not fail closed (status $unknown_status)"
[[ "$unknown_output" == *'unsupported continuity schema'* ]] ||
  fail "unknown schema failure did not name the schema"

duplicate_key_path="$test_root/duplicate-key"
init_repo "$duplicate_key_path"
(
  cd "$duplicate_key_path"
  "$state_script" snapshot >/dev/null
)
duplicate_state="$duplicate_key_path/.agent/continuity.md"
awk '{print} /^head=/ {print}' "$duplicate_state" > "$duplicate_state.tmp"
mv "$duplicate_state.tmp" "$duplicate_state"
duplicate_status=0
duplicate_output="$(
  cd "$duplicate_key_path"
  "$state_script" check 2>&1
)" || duplicate_status=$?
[[ "$duplicate_status" -ne 0 && "$duplicate_status" -ne 10 ]] ||
  fail "duplicate state field did not fail closed (status $duplicate_status)"
[[ "$duplicate_output" == *'head count=2'* ]] ||
  fail "duplicate state field failure did not name the field"

if [[ "$(id -u)" -ne 0 ]]; then
  unreadable_path="$test_root/unreadable"
  init_repo "$unreadable_path"
  (
    cd "$unreadable_path"
    "$state_script" snapshot --reason unreadable-baseline >/dev/null
  )
  unreadable_state="$unreadable_path/.agent/continuity.md"
  unreadable_checksum_before="$(cksum < "$unreadable_state")"
  printf 'blocked\n' > "$unreadable_path/blocked.txt"
  chmod 000 "$unreadable_path/blocked.txt"
  if (
    cd "$unreadable_path"
    "$state_script" snapshot --reason unreadable-attempt >/dev/null 2>&1
  ); then
    chmod 644 "$unreadable_path/blocked.txt"
    fail "snapshot reported success with an unreadable untracked entry"
  fi
  chmod 644 "$unreadable_path/blocked.txt"
  [[ "$(cksum < "$unreadable_state")" == "$unreadable_checksum_before" ]] ||
    fail "failed fingerprint replaced the previous continuity state"
  if find "$unreadable_path/.agent" -name '.continuity.*' -print -quit |
    grep -q .; then
    fail "failed fingerprint left a temporary state file"
  fi
fi

(
  cd "$repo_root"
  "$state_script" audit
) >/dev/null || fail "continuity repository did not pass its own memory audit"

printf 'PASS: continuity integration tests\n'
