#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  continuity-state.sh snapshot [--reason TEXT]
  continuity-state.sh note --objective TEXT --current-unit TEXT \
    --last-verified TEXT --next-action TEXT --blockers TEXT \
    [--authority continue|ask]
  continuity-state.sh check
  continuity-state.sh show
  continuity-state.sh audit
  continuity-state.sh handoff TOPIC
  continuity-state.sh hook
  continuity-state.sh --version

The active snapshot is .agent/continuity.md. The .agent directory must already
be ignored by Git. Audit is read-only and returns 20 when it finds a memory
policy violation. TOPIC must contain two to four lowercase kebab-case words.

check exits 0 on MATCH and 10 on repository-state drift or an obsolete
snapshot schema; refresh an obsolete snapshot with the snapshot command.
Fingerprints are derived from content through Git but store only aggregate
digests, never file contents or per-file digests.
EOF
}

die() {
  printf 'continuity-state: %s\n' "$*" >&2
  exit 1
}

repo_root=""
state_file=""
status_output=""
status_fingerprint=""
content_fingerprint=""
state_block=""
worktree_state=""
branch_name=""
head_sha=""
captured_at=""
temporary_path=""
status_preview=""
changed_path_count=0

objective=""
current_unit=""
last_verified=""
next_action=""
blockers=""
authority=""

readonly STATE_SCHEMA=2
readonly FINGERPRINT_SCOPE="index-worktree-untracked-v1"
readonly MAX_STATE_BYTES=4096
readonly MAX_WORK_FIELD_CHARS=240
readonly MAX_CHANGED_PATHS=12
readonly MAX_PATH_DISPLAY_CHARS=120
readonly MAX_AGENTS_BYTES=8192
readonly AUDIT_VIOLATION_STATUS=20

cleanup() {
  if [[ -n "${temporary_path:-}" && -e "$temporary_path" ]]; then
    rm -f "$temporary_path"
  fi
}
trap cleanup EXIT

version_command() {
  local source_path="${BASH_SOURCE[0]}"
  local source_dir
  local version_file

  while [[ -L "$source_path" ]]; do
    source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
    source_path="$(readlink "$source_path")"
    if [[ "$source_path" != /* ]]; then
      source_path="$source_dir/$source_path"
    fi
  done
  source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
  version_file="$(cd "$source_dir/../../.." && pwd)/VERSION"
  [[ -f "$version_file" ]] || die "missing version marker: $version_file"
  cat "$version_file"
}

find_repo() {
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "current directory is not inside a Git repository"
  state_file="$repo_root/.agent/continuity.md"
}

agent_state_is_safe() {
  git -C "$repo_root" check-ignore -q --no-index .agent/continuity.md
}

require_safe_agent_state() {
  agent_state_is_safe ||
    die ".agent/continuity.md is not ignored; add .agent/ to .gitignore first"
  mkdir -p "$repo_root/.agent"
}

fingerprint_status() {
  printf '%s' "$1" | cksum | awk '{print $1 ":" $2}'
}

git_quiet() {
  GIT_OPTIONAL_LOCKS=0 git -C "$repo_root" "$@"
}

read_status_text() {
  git_quiet status --porcelain=v1 --untracked-files=all
}

hash_stream() {
  git_quiet hash-object --stdin
}

# Aggregate digest of every untracked entry's path, type, and content. The
# stream is NUL-joined so unusual path characters cannot merge or split
# entries. Fails instead of skipping anything it cannot represent, so a MATCH
# never hides an unread entry.
untracked_manifest_digest() {
  git_quiet -c core.quotePath=false ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' untracked_path; do
      if [[ -L "$repo_root/$untracked_path" ]]; then
        entry_type="symlink"
        entry_digest="$(
          printf '%s' "$(readlink "$repo_root/$untracked_path")" | hash_stream
        )" || die "cannot fingerprint untracked symlink: $untracked_path"
      elif [[ -f "$repo_root/$untracked_path" ]]; then
        entry_type="file"
        if [[ -x "$repo_root/$untracked_path" ]]; then
          entry_type="executable"
        fi
        entry_digest="$(
          git_quiet hash-object --no-filters -- "$repo_root/$untracked_path"
        )" || die "cannot fingerprint untracked entry: $untracked_path"
      else
        die "unsupported untracked entry: $untracked_path"
      fi
      printf '%s\0%s\0%s\0' "$untracked_path" "$entry_type" "$entry_digest"
    done | hash_stream
}

compute_content_fingerprint() {
  local staged_digest
  local unstaged_digest
  local untracked_digest

  staged_digest="$(
    git_quiet -c diff.algorithm=myers -c core.quotePath=false \
      diff --cached --binary --no-ext-diff --no-textconv | hash_stream
  )" || die "cannot fingerprint staged state"
  unstaged_digest="$(
    git_quiet -c diff.algorithm=myers -c core.quotePath=false \
      diff --binary --no-ext-diff --no-textconv | hash_stream
  )" || die "cannot fingerprint unstaged state"
  untracked_digest="$(untracked_manifest_digest)" ||
    die "cannot fingerprint untracked state"
  printf 'staged\0%s\0unstaged\0%s\0untracked\0%s\0' \
    "$staged_digest" "$unstaged_digest" "$untracked_digest" | hash_stream
}

build_status_preview() {
  local line
  local display_line
  local visible_chars

  status_preview=""
  changed_path_count=0
  visible_chars=$((MAX_PATH_DISPLAY_CHARS - 3))
  [[ -n "$status_output" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    changed_path_count=$((changed_path_count + 1))
    if [[ "$changed_path_count" -le "$MAX_CHANGED_PATHS" ]]; then
      display_line="$line"
      if [[ "${#display_line}" -gt "$MAX_PATH_DISPLAY_CHARS" ]]; then
        display_line="${display_line:0:$visible_chars}..."
      fi
      if [[ -n "$status_preview" ]]; then
        status_preview+=$'\n'
      fi
      status_preview+="$display_line"
    fi
  done <<< "$status_output"
}

collect_git_state() {
  local status_before
  local status_after
  local attempt=0

  branch_name="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch_name" ]]; then
    branch_name="DETACHED"
  fi
  head_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)" ||
    die "repository does not have a commit yet"

  # The worktree is live, so the content fingerprint is bracketed by two
  # status reads: a race that changes the status forces one retry, then a
  # failure that preserves the previous state. Content changing while the
  # status stays identical yields a digest of one observed read.
  while :; do
    status_before="$(read_status_text)" || die "cannot read Git status"
    content_fingerprint="$(compute_content_fingerprint)" ||
      die "content fingerprint failed; previous continuity state is unchanged"
    status_after="$(read_status_text)" || die "cannot read Git status"
    if [[ "$status_before" == "$status_after" ]]; then
      break
    fi
    attempt=$((attempt + 1))
    [[ "$attempt" -lt 2 ]] ||
      die "repository changed during fingerprint capture; retry when the worktree is quiet"
  done

  status_output="$status_before"
  status_fingerprint="$(fingerprint_status "$status_output")"
  build_status_preview
  if [[ -n "$status_output" ]]; then
    worktree_state="dirty"
  else
    worktree_state="clean"
  fi
  captured_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

read_field() {
  local label="$1"
  local value
  value="$(sed -n "s/^- ${label}: //p" "$state_file" 2>/dev/null | head -n 1)"
  printf '%s' "$value"
}

load_notes() {
  if [[ -f "$state_file" ]]; then
    objective="$(read_field "Objective")"
    current_unit="$(read_field "Current unit")"
    last_verified="$(read_field "Last verified")"
    next_action="$(read_field "Next action")"
    blockers="$(read_field "Blockers")"
    authority="$(read_field "Authority")"
  fi

  objective="${objective:-TODO}"
  current_unit="${current_unit:-TODO}"
  last_verified="${last_verified:-TODO}"
  next_action="${next_action:-TODO}"
  blockers="${blockers:-None}"
  authority="${authority:-continue}"
}

validate_one_line() {
  local label="$1"
  local value="$2"
  local limit="${3:-$MAX_WORK_FIELD_CHARS}"
  [[ -n "$value" ]] || die "$label cannot be empty"
  case "$value" in
    *$'\n'*|*$'\r'*)
      die "$label must be one line"
      ;;
  esac
  [[ "${#value}" -le "$limit" ]] ||
    die "$label exceeds $limit characters"
}

validate_work_state() {
  validate_one_line "objective" "$objective"
  validate_one_line "current unit" "$current_unit"
  validate_one_line "last verified" "$last_verified"
  validate_one_line "next action" "$next_action"
  validate_one_line "blockers" "$blockers"
  [[ "$authority" == "continue" || "$authority" == "ask" ]] ||
    die "authority must be continue or ask"
}

write_state() {
  local reason="$1"
  local state_bytes

  validate_one_line "reason" "$reason"
  validate_work_state
  require_safe_agent_state
  collect_git_state

  temporary_path="$(mktemp "$repo_root/.agent/.continuity.XXXXXX")"
  chmod 600 "$temporary_path"

  {
    printf '# Continuity\n\n'
    printf '<!-- continuity-state\n'
    printf 'schema=%s\n' "$STATE_SCHEMA"
    printf 'captured_at=%s\n' "$captured_at"
    printf 'reason=%s\n' "$reason"
    printf 'repo_root=%s\n' "$repo_root"
    printf 'branch=%s\n' "$branch_name"
    printf 'head=%s\n' "$head_sha"
    printf 'worktree=%s\n' "$worktree_state"
    printf 'fingerprint_scope=%s\n' "$FINGERPRINT_SCOPE"
    printf 'status_fingerprint=%s\n' "$status_fingerprint"
    printf 'content_fingerprint=%s\n' "$content_fingerprint"
    printf '%s\n\n' '-->'
    printf '## Changed paths\n\n'
    printf '%s\n' '```text'
    if [[ -n "$status_output" ]]; then
      printf '%s\n' "$status_preview"
      if [[ "$changed_path_count" -gt "$MAX_CHANGED_PATHS" ]]; then
        printf '(showing %s of %s changed paths; run git status --short for full list)\n' \
          "$MAX_CHANGED_PATHS" "$changed_path_count"
      fi
    else
      printf '%s\n' '(clean)'
    fi
    printf '%s\n\n' '```'
    printf '## Work state\n\n'
    printf -- '- Objective: %s\n' "$objective"
    printf -- '- Current unit: %s\n' "$current_unit"
    printf -- '- Last verified: %s\n' "$last_verified"
    printf -- '- Next action: %s\n' "$next_action"
    printf -- '- Blockers: %s\n' "$blockers"
    printf -- '- Authority: %s\n' "$authority"
  } > "$temporary_path"

  state_bytes="$(wc -c < "$temporary_path" | tr -d ' ')"
  [[ "$state_bytes" -le "$MAX_STATE_BYTES" ]] ||
    die "generated continuity state is $state_bytes bytes; limit is $MAX_STATE_BYTES"

  mv "$temporary_path" "$state_file"
  temporary_path=""
}

load_state_block() {
  state_block="$(sed -n '/^<!-- continuity-state$/,/^-->$/p' "$state_file")"
  [[ -n "$state_block" ]] ||
    die "continuity snapshot has no state block; refresh with the snapshot command"
}

read_state_key() {
  local key="$1"
  local field_count

  field_count="$(
    printf '%s\n' "$state_block" |
      LC_ALL=C awk -v prefix="${key}=" '
        index($0, prefix) == 1 { count++ }
        END { print count + 0 }
      '
  )"
  [[ "$field_count" -eq 1 ]] ||
    die "continuity snapshot field ${key} count=${field_count} expected=1; refresh with the snapshot command"
  printf '%s\n' "$state_block" | sed -n "s/^${key}=//p" | head -n 1
}

snapshot_command() {
  local reason="manual"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason)
        [[ $# -ge 2 ]] || die "--reason requires text"
        reason="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown snapshot option: $1"
        ;;
    esac
  done

  find_repo
  load_notes
  write_state "$reason"
  printf '%s\n' "$state_file"
}

note_command() {
  local have_objective=0
  local have_current_unit=0
  local have_last_verified=0
  local have_next_action=0
  local have_blockers=0

  objective=""
  current_unit=""
  last_verified=""
  next_action=""
  blockers=""
  authority="continue"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --objective)
        [[ $# -ge 2 ]] || die "--objective requires text"
        objective="$2"
        have_objective=1
        shift 2
        ;;
      --current-unit)
        [[ $# -ge 2 ]] || die "--current-unit requires text"
        current_unit="$2"
        have_current_unit=1
        shift 2
        ;;
      --last-verified)
        [[ $# -ge 2 ]] || die "--last-verified requires text"
        last_verified="$2"
        have_last_verified=1
        shift 2
        ;;
      --next-action)
        [[ $# -ge 2 ]] || die "--next-action requires text"
        next_action="$2"
        have_next_action=1
        shift 2
        ;;
      --blockers)
        [[ $# -ge 2 ]] || die "--blockers requires text"
        blockers="$2"
        have_blockers=1
        shift 2
        ;;
      --authority)
        [[ $# -ge 2 ]] || die "--authority requires continue or ask"
        authority="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown note option: $1"
        ;;
    esac
  done

  [[ "$have_objective" -eq 1 ]] || die "--objective is required"
  [[ "$have_current_unit" -eq 1 ]] || die "--current-unit is required"
  [[ "$have_last_verified" -eq 1 ]] || die "--last-verified is required"
  [[ "$have_next_action" -eq 1 ]] || die "--next-action is required"
  [[ "$have_blockers" -eq 1 ]] || die "--blockers is required"
  [[ "$authority" == "continue" || "$authority" == "ask" ]] ||
    die "--authority must be continue or ask"

  validate_one_line "objective" "$objective"
  validate_one_line "current unit" "$current_unit"
  validate_one_line "last verified" "$last_verified"
  validate_one_line "next action" "$next_action"
  validate_one_line "blockers" "$blockers"

  find_repo
  write_state "note"
  printf '%s\n' "$state_file"
}

check_command() {
  local recorded_schema
  local recorded_scope
  local recorded_root
  local recorded_branch
  local recorded_head
  local recorded_fingerprint
  local recorded_content
  local drift=0

  find_repo
  [[ -f "$state_file" ]] || die "no continuity snapshot at $state_file"
  load_state_block

  recorded_schema="$(read_state_key schema)"
  case "$recorded_schema" in
    "$STATE_SCHEMA")
      ;;
    1)
      printf 'DRIFT schema recorded=1 required=%s; refresh with the snapshot command\n' \
        "$STATE_SCHEMA"
      return 10
      ;;
    *)
      die "unsupported continuity schema: $recorded_schema"
      ;;
  esac

  recorded_scope="$(read_state_key fingerprint_scope)"
  [[ "$recorded_scope" == "$FINGERPRINT_SCOPE" ]] ||
    die "unsupported fingerprint scope: $recorded_scope"

  recorded_root="$(read_state_key repo_root)"
  recorded_branch="$(read_state_key branch)"
  recorded_head="$(read_state_key head)"
  recorded_fingerprint="$(read_state_key status_fingerprint)"
  recorded_content="$(read_state_key content_fingerprint)"
  [[ -n "$recorded_root" && -n "$recorded_branch" &&
     -n "$recorded_head" && -n "$recorded_fingerprint" &&
     -n "$recorded_content" ]] ||
    die "continuity snapshot is incomplete"

  collect_git_state

  if [[ "$recorded_root" != "$repo_root" ]]; then
    printf 'DRIFT repo_root recorded=%s current=%s\n' "$recorded_root" "$repo_root"
    drift=1
  fi
  if [[ "$recorded_branch" != "$branch_name" ]]; then
    printf 'DRIFT branch recorded=%s current=%s\n' "$recorded_branch" "$branch_name"
    drift=1
  fi
  if [[ "$recorded_head" != "$head_sha" ]]; then
    printf 'DRIFT head recorded=%s current=%s\n' "$recorded_head" "$head_sha"
    drift=1
  fi
  if [[ "$recorded_fingerprint" != "$status_fingerprint" ]]; then
    printf 'DRIFT worktree recorded=%s current=%s\n' \
      "$recorded_fingerprint" "$status_fingerprint"
    drift=1
  fi
  if [[ "$recorded_content" != "$content_fingerprint" ]]; then
    printf 'DRIFT content recorded=%s current=%s\n' \
      "$recorded_content" "$content_fingerprint"
    drift=1
  fi

  if [[ "$drift" -eq 1 ]]; then
    return 10
  fi

  printf 'MATCH branch=%s head=%s worktree=%s\n' \
    "$branch_name" "$head_sha" "$worktree_state"
}

show_command() {
  find_repo
  [[ -f "$state_file" ]] || die "no continuity snapshot at $state_file"
  cat "$state_file"
}

audit_field() {
  local label="$1"
  local value="$2"
  local field_count

  field_count="$(
    LC_ALL=C awk -v prefix="- ${label}: " '
      index($0, prefix) == 1 { count++ }
      END { print count + 0 }
    ' "$state_file"
  )"
  if [[ "$field_count" -ne 1 ]]; then
    printf 'VIOLATION continuity-state field-count=%s count=%s expected=1\n' \
      "$label" "$field_count"
    audit_issues=$((audit_issues + 1))
    return 0
  fi

  if [[ -z "$value" ]]; then
    printf 'VIOLATION continuity-state field-missing=%s\n' "$label"
    audit_issues=$((audit_issues + 1))
  elif [[ "$value" == "TODO" ]]; then
    printf 'VIOLATION continuity-state field-placeholder=%s\n' "$label"
    audit_issues=$((audit_issues + 1))
  elif [[ "${#value}" -gt "$MAX_WORK_FIELD_CHARS" ]]; then
    printf 'VIOLATION continuity-state field=%s chars=%s limit=%s\n' \
      "$label" "${#value}" "$MAX_WORK_FIELD_CHARS"
    audit_issues=$((audit_issues + 1))
  fi
}

audit_command() {
  local agents_path
  local agents_bytes
  local duplicate_output
  local state_bytes
  local check_output
  local check_status
  local handoff_files
  local handoff_file
  local handoff_status
  local normalized_status
  local handoff_violations=0
  local audit_issues=0

  find_repo
  agents_path="$repo_root/AGENTS.md"

  if [[ -f "$agents_path" ]]; then
    agents_bytes="$(wc -c < "$agents_path" | tr -d ' ')"
    if [[ "$agents_bytes" -gt "$MAX_AGENTS_BYTES" ]]; then
      printf 'VIOLATION agents-size path=AGENTS.md bytes=%s limit=%s\n' \
        "$agents_bytes" "$MAX_AGENTS_BYTES"
      audit_issues=$((audit_issues + 1))
    else
      printf 'PASS agents-size path=AGENTS.md bytes=%s limit=%s\n' \
        "$agents_bytes" "$MAX_AGENTS_BYTES"
    fi

    duplicate_output="$(
      LC_ALL=C awk '
        function flush_bullet( normalized) {
          if (bullet == "") {
            return
          }
          normalized = bullet
          gsub(/[[:space:]]+/, " ", normalized)
          sub(/^[[:space:]]+/, "", normalized)
          sub(/[[:space:]]+$/, "", normalized)
          if (length(normalized) >= 32) {
            if (seen[normalized]++) {
              printf "VIOLATION duplicate-instruction path=AGENTS.md line=%d text=%s\n", bullet_line, normalized
            }
          }
          bullet = ""
          bullet_line = 0
        }
        {
          raw = $0
          stripped = raw
          sub(/^[[:space:]]*/, "", stripped)
          if (substr(stripped, 1, 3) == "```" ||
              substr(stripped, 1, 3) == "~~~") {
            if (!in_fence) {
              flush_bullet()
            }
            in_fence = !in_fence
            next
          }
          if (in_fence) {
            next
          }
          if (raw ~ /^[[:space:]]*-[[:space:]]+/) {
            flush_bullet()
            bullet = raw
            sub(/^[[:space:]]*-[[:space:]]+/, "", bullet)
            bullet_line = NR
            next
          }
          if (bullet != "" && raw ~ /^[[:space:]]+[^[:space:]]/) {
            continuation = raw
            sub(/^[[:space:]]+/, "", continuation)
            bullet = bullet " " continuation
            next
          }
          flush_bullet()
        }
        END { flush_bullet() }
      ' "$agents_path"
    )"
    if [[ -n "$duplicate_output" ]]; then
      printf '%s\n' "$duplicate_output"
      while IFS= read -r _; do
        audit_issues=$((audit_issues + 1))
      done <<< "$duplicate_output"
    else
      printf 'PASS duplicate-instructions path=AGENTS.md\n'
    fi
  else
    printf 'INFO agents-size path=AGENTS.md missing\n'
    printf 'INFO duplicate-instructions path=AGENTS.md not-checked\n'
  fi

  if [[ -f "$state_file" ]]; then
    state_bytes="$(wc -c < "$state_file" | tr -d ' ')"
    if [[ "$state_bytes" -gt "$MAX_STATE_BYTES" ]]; then
      printf 'VIOLATION continuity-state bytes=%s limit=%s\n' \
        "$state_bytes" "$MAX_STATE_BYTES"
      audit_issues=$((audit_issues + 1))
    else
      printf 'PASS continuity-state-size bytes=%s limit=%s\n' \
        "$state_bytes" "$MAX_STATE_BYTES"
    fi

    objective="$(read_field "Objective")"
    current_unit="$(read_field "Current unit")"
    last_verified="$(read_field "Last verified")"
    next_action="$(read_field "Next action")"
    blockers="$(read_field "Blockers")"
    authority="$(read_field "Authority")"
    audit_field "Objective" "$objective"
    audit_field "Current unit" "$current_unit"
    audit_field "Last verified" "$last_verified"
    audit_field "Next action" "$next_action"
    audit_field "Blockers" "$blockers"
    audit_field "Authority" "$authority"
    if [[ -n "$authority" && "$authority" != "continue" &&
          "$authority" != "ask" ]]; then
      printf 'VIOLATION continuity-state authority=%s expected=continue-or-ask\n' \
        "$authority"
      audit_issues=$((audit_issues + 1))
    fi

    if check_output="$(check_command 2>&1)"; then
      printf 'PASS continuity-state match\n'
    else
      check_status=$?
      printf 'VIOLATION continuity-state drift status=%s detail=%s\n' \
        "$check_status" "$(printf '%s' "$check_output" | tr '\n' ';')"
      audit_issues=$((audit_issues + 1))
    fi
  else
    printf 'INFO continuity-state missing\n'
  fi

  handoff_files="$(git -C "$repo_root" ls-files 'handoffs/*.md')"
  if [[ -n "$handoff_files" ]]; then
    while IFS= read -r handoff_file; do
      [[ -n "$handoff_file" ]] || continue
      handoff_status="$(
        sed -n 's/^Status:[[:space:]]*//p' "$repo_root/$handoff_file" |
          head -n 1
      )"
      normalized_status="$(
        printf '%s' "$handoff_status" |
          sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
          tr '[:upper:]' '[:lower:]'
      )"
      case "$normalized_status" in
        active|current|"in progress")
          printf 'VIOLATION handoff-status path=%s status=%s\n' \
            "$handoff_file" "$handoff_status"
          audit_issues=$((audit_issues + 1))
          handoff_violations=$((handoff_violations + 1))
          ;;
      esac
    done <<< "$handoff_files"
  fi
  if [[ "$handoff_violations" -eq 0 ]]; then
    printf 'PASS handoff-status tracked-active=0\n'
  fi

  if [[ "$audit_issues" -gt 0 ]]; then
    printf 'SUMMARY violations=%s\n' "$audit_issues"
    return "$AUDIT_VIOLATION_STATUS"
  fi

  printf 'SUMMARY violations=0\n'
}

notes_are_complete() {
  local value
  for value in "$objective" "$current_unit" "$last_verified" "$next_action"; do
    [[ -n "$value" && "$value" != "TODO" ]] || return 1
  done
}

handoff_command() {
  local topic
  local word_count
  local highest=0
  local existing
  local base
  local prefix
  local prefix_number
  local next_number
  local handoff_dir
  local handoff_path
  local handoff_temp
  local handoff_date

  [[ $# -eq 2 ]] || die "handoff requires one topic"
  topic="$2"
  [[ "$topic" =~ ^[a-z0-9]+(-[a-z0-9]+){1,3}$ ]] ||
    die "topic must contain two to four lowercase kebab-case words"
  word_count="$(awk -F- '{print NF}' <<< "$topic")"
  [[ "$word_count" -ge 2 && "$word_count" -le 4 ]] ||
    die "topic must contain two to four words"

  find_repo
  load_notes
  notes_are_complete ||
    die "objective, current unit, last verified, and next action must be complete"
  write_state "handoff"
  collect_git_state

  handoff_dir="$repo_root/handoffs"
  if [[ -e "$handoff_dir" || -L "$handoff_dir" ]]; then
    [[ ! -L "$handoff_dir" && -d "$handoff_dir" ]] ||
      die "handoff directory must be a real directory inside the repository"
  else
    mkdir "$handoff_dir"
  fi
  for existing in "$handoff_dir"/[0-9][0-9][0-9]-handoff-*.md; do
    [[ -e "$existing" ]] || continue
    base="$(basename "$existing")"
    prefix="${base%%-*}"
    [[ "$prefix" =~ ^[0-9]{3}$ ]] || continue
    prefix_number=$((10#$prefix))
    if [[ "$prefix_number" -gt "$highest" ]]; then
      highest="$prefix_number"
    fi
  done

  next_number="$(printf '%03d' "$((highest + 1))")"
  handoff_date="$(date '+%Y-%m-%d')"
  handoff_path="$handoff_dir/${next_number}-handoff-${topic}-${handoff_date}.md"
  handoff_temp="$(mktemp "$handoff_dir/.handoff.XXXXXX")"
  temporary_path="$handoff_temp"

  # shellcheck disable=SC2016  # backtick spans are literal Markdown output
  {
    printf '# Handoff: %s\n\n' "$topic"
    printf 'Date: %s\n' "$handoff_date"
    printf 'Status: Boundary snapshot\n\n'
    printf '## Objective\n\n%s\n\n' "$objective"
    printf '## Current unit\n\n%s\n\n' "$current_unit"
    printf '## Last verified\n\n%s\n\n' "$last_verified"
    printf '## Next action\n\n%s\n\n' "$next_action"
    printf '## Blockers\n\n%s\n\n' "$blockers"
    printf '## Authority\n\n%s\n\n' "$authority"
    printf '## Repository state\n\n'
    printf -- '- Branch: `%s`\n' "$branch_name"
    printf -- '- HEAD: `%s`\n' "$head_sha"
    printf -- '- Worktree: `%s`\n' "$worktree_state"
    printf -- '- Changed path count: `%s`\n' "$changed_path_count"
    printf -- '- Status fingerprint: `%s`\n' "$status_fingerprint"
    printf -- '- Content fingerprint: `%s`\n\n' "$content_fingerprint"
    printf '## Resume contract\n\n'
    printf '1. Verify the branch, HEAD, and working tree against this snapshot.\n'
    printf '2. Read only the durable sources needed for the current unit.\n'
    printf '3. Re-run the narrowest check needed to confirm current truth.\n'
    printf '4. Continue the next action without asking when it remains authorized.\n'
  } > "$handoff_temp"

  if ! ln "$handoff_temp" "$handoff_path" 2>/dev/null; then
    die "handoff target already exists: $handoff_path"
  fi
  rm -f "$handoff_temp"
  temporary_path=""
  printf '%s\n' "$handoff_path"
}

# Best-effort entry point: ineligible repositories exit 0 silently so the
# hook never blocks another tool. Failures are only reported once an actual
# snapshot attempt begins in an eligible repository.
hook_command() {
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo_root" ]] || exit 0
  state_file="$repo_root/.agent/continuity.md"
  [[ -d "$repo_root/.agent" ]] || exit 0
  agent_state_is_safe || exit 0
  git -C "$repo_root" rev-parse --verify HEAD >/dev/null 2>&1 || exit 0
  load_notes
  write_state "pre-compact"
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  snapshot)
    snapshot_command "$@"
    ;;
  note)
    note_command "$@"
    ;;
  check)
    [[ $# -eq 1 ]] || die "check does not accept arguments"
    check_command
    ;;
  show)
    [[ $# -eq 1 ]] || die "show does not accept arguments"
    show_command
    ;;
  audit)
    [[ $# -eq 1 ]] || die "audit does not accept arguments"
    audit_command
    ;;
  handoff)
    handoff_command "$@"
    ;;
  hook)
    [[ $# -eq 1 ]] || die "hook does not accept arguments"
    hook_command
    ;;
  --version)
    [[ $# -eq 1 ]] || die "--version does not accept arguments"
    version_command
    ;;
  -h|--help)
    usage
    ;;
  *)
    die "unknown command: $1"
    ;;
esac
