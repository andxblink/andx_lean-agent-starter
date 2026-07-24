#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_path="$repo_root/bin/andx-project"
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

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  grep -F -- "$expected" "$file_path" >/dev/null ||
    fail "expected '$expected' in $file_path"
}

# shellcheck disable=SC2016  # the unexpanded $() text is the fixture itself
purpose='Literal $(touch should-not-exist) & / \ value'
project_path="$test_root/example-project"
"$command_path" init "$project_path" --purpose "$purpose" >/dev/null

for file_path in \
  README.md \
  AGENTS.md \
  CLAUDE.md \
  GEMINI.md \
  .gitignore \
  .andx-starter \
  docs/.gitkeep \
  planning/.gitkeep \
  handoffs/.gitkeep \
  scripts/.gitkeep \
  swarms/.gitkeep; do
  assert_file "$project_path/$file_path"
done

for dir_path in docs planning handoffs scripts swarms temp .agent; do
  assert_dir "$project_path/$dir_path"
done
assert_dir "$project_path/.git"

project_path_canonical="$(cd "$project_path" && pwd -P)"
project_git_root="$(git -C "$project_path" rev-parse --show-toplevel)"
[[ "$project_git_root" == "$project_path_canonical" ]] ||
  fail "generated project did not become its own Git repository"
[[ -z "$(git -C "$project_path" remote)" ]] ||
  fail "generated project should not inherit or configure a Git remote"

actual_tree="$test_root/actual-tree.txt"
expected_tree="$test_root/expected-tree.txt"
(
  cd "$project_path"
  find . -path ./.git -prune -o -print | LC_ALL=C sort
) > "$actual_tree"
printf '%s\n' \
  . \
  ./.agent \
  ./.andx-starter \
  ./.gitignore \
  ./AGENTS.md \
  ./CLAUDE.md \
  ./GEMINI.md \
  ./README.md \
  ./docs \
  ./docs/.gitkeep \
  ./handoffs \
  ./handoffs/.gitkeep \
  ./planning \
  ./planning/.gitkeep \
  ./scripts \
  ./scripts/.gitkeep \
  ./swarms \
  ./swarms/.gitkeep \
  ./temp > "$expected_tree"
diff -u "$expected_tree" "$actual_tree" ||
  fail "generated tree differs"

# shellcheck disable=SC2016  # backtick spans are literal generated Markdown
{
  assert_contains "$project_path/README.md" "$purpose"
  assert_contains "$project_path/README.md" 'No runtime has been selected.'
  assert_contains "$project_path/README.md" 'No project-specific check exists yet.'
  assert_contains "$project_path/README.md" '| `docs/` | Current durable project knowledge |'
  assert_contains "$project_path/AGENTS.md" 'Work in low-interaction mode by default.'
  assert_contains "$project_path/AGENTS.md" 'When the current agent supports delegated workers'
  assert_contains "$project_path/AGENTS.md" 'Treat worker summaries as untrusted reports.'
  assert_contains "$project_path/AGENTS.md" 'Only the primary agent updates shared continuity state.'
  assert_contains "$project_path/AGENTS.md" 'Keep one related objective in the same session'
  assert_contains "$project_path/AGENTS.md" 'Use the continuity skill or `andx-continuity` command'
  assert_contains "$project_path/AGENTS.md" 'Keep replaceable active state in ignored `.agent/continuity.md`.'
  assert_contains "$project_path/AGENTS.md" 'Use a verified worker harness when available'
  assert_contains "$project_path/README.md" '| `swarms/` | Optional multi-agent task manifests and executable checks |'
  assert_contains "$project_path/README.md" '`AGENTS.md` is the canonical operating contract.'
  assert_contains "$project_path/README.md" '| `.agent/` | Live continuity and replaceable agent state; never commit |'
  printf '%s\n' \
    'Read and follow `AGENTS.md` as the canonical project instructions.' \
    > "$test_root/expected-adapter.txt"
}
cmp "$test_root/expected-adapter.txt" "$project_path/CLAUDE.md" ||
  fail "Claude adapter does not point to the canonical rules exactly"
cmp "$test_root/expected-adapter.txt" "$project_path/GEMINI.md" ||
  fail "Gemini adapter does not point to the canonical rules exactly"
if grep -E 'Codex|Claude|Gemini|Copilot|Cursor|OpenCode' \
  "$project_path/AGENTS.md" >/dev/null; then
  fail "canonical project rules contain vendor-specific language"
fi
assert_contains "$project_path/.gitignore" '.env'
assert_contains "$project_path/.gitignore" '.agent/'
assert_contains "$project_path/.gitignore" 'temp/'
[[ ! -e "$test_root/should-not-exist" ]] ||
  fail "purpose text was executed"

if "$command_path" init "$project_path" >/dev/null 2>&1; then
  fail "second initialization should fail"
fi
assert_contains "$project_path/README.md" "$purpose"

parent_repo="$test_root/parent-repository"
mkdir -p "$parent_repo"
git -C "$parent_repo" init -q
nested_project="$parent_repo/generated-project"
GIT_DIR="$parent_repo/.git" \
GIT_WORK_TREE="$parent_repo" \
  "$command_path" init "$nested_project" >/dev/null
nested_project_canonical="$(cd "$nested_project" && pwd -P)"
nested_git_root="$(git -C "$nested_project" rev-parse --show-toplevel)"
[[ "$nested_git_root" == "$nested_project_canonical" ]] ||
  fail "project created below another checkout inherited its parent commit target"
[[ -z "$(git -C "$nested_project" remote)" ]] ||
  fail "nested project inherited a Git remote"

dry_path="$test_root/dry-project"
"$command_path" init "$dry_path" --purpose "Dry run" --dry-run >/dev/null
[[ ! -e "$dry_path" ]] || fail "dry-run created the target"

sentinel_path="$test_root/non-empty"
mkdir -p "$sentinel_path"
printf '%s\n' "preserve me" > "$sentinel_path/sentinel.txt"
if "$command_path" init "$sentinel_path" >/dev/null 2>&1; then
  fail "non-empty target should fail"
fi
assert_contains "$sentinel_path/sentinel.txt" "preserve me"
[[ ! -e "$sentinel_path/README.md" ]] ||
  fail "non-empty target was partially modified"

empty_path="$test_root/empty"
mkdir -p "$empty_path"
(umask 022; "$command_path" init "$empty_path" >/dev/null)
assert_file "$empty_path/README.md"
assert_contains "$empty_path/README.md" 'TODO: Describe this project in one sentence.'
if root_mode="$(stat -f '%Lp' "$empty_path" 2>/dev/null)"; then
  :
else
  root_mode="$(stat -c '%a' "$empty_path")"
fi
[[ "$root_mode" == "755" ]] ||
  fail "project root mode should respect umask 022, got $root_mode"

dot_path="$test_root/dot-project"
mkdir -p "$dot_path"
(
  cd "$dot_path"
  "$command_path" init . >/dev/null
)
assert_file "$dot_path/README.md"
assert_contains "$dot_path/README.md" '# dot-project'

ambiguous_parent="$test_root/ambiguous-parent"
if "$command_path" init "$ambiguous_parent/../ambiguous-project" >/dev/null 2>&1; then
  fail "path containing '..' should fail"
fi
[[ ! -e "$ambiguous_parent" ]] ||
  fail "ambiguous path created an unrelated parent"
[[ ! -e "$test_root/ambiguous-project" ]] ||
  fail "ambiguous path created a project"

file_target="$test_root/file-target"
printf '%s\n' "preserve me" > "$file_target"
if "$command_path" init "$file_target" >/dev/null 2>&1; then
  fail "file target should fail"
fi
assert_contains "$file_target" "preserve me"

if "$command_path" init >/dev/null 2>&1; then
  fail "missing target should fail"
fi
"$command_path" init --help >/dev/null ||
  fail "init help should succeed"
if "$command_path" init --dry-run >/dev/null 2>&1; then
  fail "an option should not be accepted as the target path"
fi
if "$command_path" unknown "$test_root/unknown" >/dev/null 2>&1; then
  fail "unknown command should fail"
fi
if "$command_path" init "$test_root/unknown-option" --unknown >/dev/null 2>&1; then
  fail "unknown option should fail"
fi

symlink_destination="$test_root/symlink-destination"
symlink_target="$test_root/symlink-target"
mkdir -p "$symlink_destination"
ln -s "$symlink_destination" "$symlink_target"
if "$command_path" init "$symlink_target" >/dev/null 2>&1; then
  fail "symlink target should fail"
fi
[[ -L "$symlink_target" ]] || fail "symlink target was changed"
[[ -z "$(find "$symlink_destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  fail "symlink destination was changed"

race_path="$test_root/race-project"
race_path_canonical="$(cd "$test_root" && pwd -P)/race-project"
race_bin="$test_root/race-bin"
mkdir -p "$race_bin"
real_mkdir="$(command -v mkdir)"
sed \
  -e "s|__REAL_MKDIR__|$real_mkdir|g" \
  -e "s|__RACE_TARGET__|$race_path_canonical|g" \
  "$repo_root/tests/fixtures/racing-mkdir.sh" > "$race_bin/mkdir"
chmod +x "$race_bin/mkdir"
if PATH="$race_bin:$PATH" "$command_path" init "$race_path" >/dev/null 2>&1; then
  fail "initializer should lose a forced target race"
fi
assert_file "$race_path/racer-sentinel.txt"
[[ ! -e "$race_path/README.md" ]] ||
  fail "initializer wrote into a directory claimed by another process"

post_claim_path="$test_root/post-claim-race"
post_claim_path_canonical="$(cd "$test_root" && pwd -P)/post-claim-race"
post_claim_bin="$test_root/post-claim-bin"
mkdir -p "$post_claim_bin"
real_cp="$(command -v cp)"
sed \
  -e "s|__REAL_CP__|$real_cp|g" \
  -e "s|__RACE_TARGET__|$post_claim_path_canonical|g" \
  "$repo_root/tests/fixtures/racing-cp.sh" > "$post_claim_bin/cp"
chmod +x "$post_claim_bin/cp"
if PATH="$post_claim_bin:$PATH" \
  "$command_path" init "$post_claim_path" >/dev/null 2>&1; then
  fail "initializer should fail after a forced post-claim replacement"
fi
assert_file "$post_claim_path/racer-sentinel.txt"
assert_contains "$post_claim_path/racer-sentinel.txt" "replacement must survive"
[[ ! -e "$post_claim_path/README.md" ]] ||
  fail "initializer populated a post-claim replacement"
assert_file "$post_claim_path.claimed/README.md"

printf 'PASS: andx-project integration tests\n'
