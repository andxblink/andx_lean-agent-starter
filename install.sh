#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--dry-run] [--skill-dir ABSOLUTE_PATH]...
  ./install.sh --uninstall [--dry-run] [--skill-dir ABSOLUTE_PATH]...

Always manage only:
  ~/.local/bin/andx-project
  ~/.local/bin/andx-continuity

Each --skill-dir additionally manages:
  ABSOLUTE_PATH/continuity

Use --skill-dir for any Agent Skills-compatible discovery directory. The
installer never modifies agent configuration, global instruction files,
plugins, hooks, or project trust.
EOF
}

die() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

resolve_repo_root() {
  cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

dry_run=0
uninstall=0
skill_dirs=()
skill_dir_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --uninstall)
      uninstall=1
      shift
      ;;
    --skill-dir)
      [[ $# -ge 2 ]] || die "--skill-dir requires a path"
      skill_dir="$2"
      [[ "$skill_dir" == /* ]] ||
        die "--skill-dir must be an absolute path: $skill_dir"
      [[ "$skill_dir" != "/" ]] ||
        die "--skill-dir cannot be the filesystem root"
      case "/$skill_dir/" in
        *"/../"*|*"/./"*)
          die "--skill-dir cannot contain '.' or '..' segments: $skill_dir"
          ;;
      esac
      skill_dir="${skill_dir%/}"
      duplicate=0
      index=0
      while [[ "$index" -lt "$skill_dir_count" ]]; do
        if [[ "${skill_dirs[$index]}" == "$skill_dir" ]]; then
          duplicate=1
          break
        fi
        index=$((index + 1))
      done
      if [[ "$duplicate" -eq 0 ]]; then
        skill_dirs[skill_dir_count]="$skill_dir"
        skill_dir_count=$((skill_dir_count + 1))
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

repo_root="$(resolve_repo_root)"
command_source="$repo_root/bin/andx-project"
continuity_source="$repo_root/bin/andx-continuity"
skill_source="$repo_root/skills/continuity"
command_target="$HOME/.local/bin/andx-project"
continuity_target="$HOME/.local/bin/andx-continuity"

sources=("$command_source" "$continuity_source")
targets=("$command_target" "$continuity_target")
target_count=2
index=0
while [[ "$index" -lt "$skill_dir_count" ]]; do
  sources[target_count]="$skill_source"
  targets[target_count]="${skill_dirs[$index]}/continuity"
  target_count=$((target_count + 1))
  index=$((index + 1))
done

target_matches() {
  local target="$1"
  local source="$2"
  [[ -L "$target" && "$(readlink "$target")" == "$source" ]]
}

preflight_target() {
  local target="$1"
  local source="$2"
  local link_target

  if [[ -e "$target" || -L "$target" ]]; then
    if ! target_matches "$target" "$source"; then
      printf 'install: refusing unrelated destination: %s\n' "$target" >&2
      if [[ -L "$target" ]]; then
        link_target="$(readlink "$target")"
        printf 'install: currently a symlink to: %s\n' "$link_target" >&2
        case "$link_target" in
          */bin/andx-project|*/bin/andx-continuity|*/skills/continuity)
            printf 'install: this looks like another checkout of this tool; run ./install.sh --uninstall from that checkout first\n' >&2
            ;;
        esac
      elif [[ -d "$target" ]]; then
        printf 'install: currently a directory\n' >&2
      else
        printf 'install: currently a regular file\n' >&2
      fi
      exit 1
    fi
  fi
}

if [[ "$uninstall" -eq 1 ]]; then
  printf 'Uninstall targets:\n'
  index=0
  while [[ "$index" -lt "$target_count" ]]; do
    printf '  %s\n' "${targets[$index]}"
    index=$((index + 1))
  done
  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Dry run: no changes made.\n'
    exit 0
  fi
  index=0
  while [[ "$index" -lt "$target_count" ]]; do
    if target_matches "${targets[$index]}" "${sources[$index]}"; then
      unlink "${targets[$index]}"
    elif [[ -e "${targets[$index]}" || -L "${targets[$index]}" ]]; then
      printf 'Skipped unrelated destination: %s\n' "${targets[$index]}" >&2
    fi
    index=$((index + 1))
  done
  printf 'Uninstalled repository-managed links.\n'
  exit 0
fi

[[ -x "$command_source" ]] ||
  die "missing executable command source: $command_source"
[[ -x "$continuity_source" ]] ||
  die "missing executable continuity source: $continuity_source"
[[ -f "$skill_source/SKILL.md" &&
   -x "$skill_source/scripts/continuity-state.sh" ]] ||
  die "missing continuity skill source: $skill_source"

index=0
while [[ "$index" -lt "$target_count" ]]; do
  preflight_target "${targets[$index]}" "${sources[$index]}"
  index=$((index + 1))
done

printf 'Install targets:\n'
index=0
while [[ "$index" -lt "$target_count" ]]; do
  printf '  %s -> %s\n' "${targets[$index]}" "${sources[$index]}"
  index=$((index + 1))
done
if [[ "$dry_run" -eq 1 ]]; then
  printf 'Dry run: no changes made.\n'
  exit 0
fi

created_targets=()
created_sources=()
created_target_count=0
rollback_created() {
  local rollback_index="$created_target_count"
  local rollback_target
  local rollback_source

  while [[ "$rollback_index" -gt 0 ]]; do
    rollback_index=$((rollback_index - 1))
    rollback_target="${created_targets[$rollback_index]}"
    rollback_source="${created_sources[$rollback_index]}"
    if target_matches "$rollback_target" "$rollback_source"; then
      unlink "$rollback_target"
    fi
  done
}

install_in_progress=1
cleanup_install() {
  if [[ "${install_in_progress:-0}" -eq 1 ]]; then
    rollback_created
  fi
}
trap cleanup_install EXIT

index=0
while [[ "$index" -lt "$target_count" ]]; do
  target="${targets[$index]}"
  source="${sources[$index]}"
  if ! mkdir -p "$(dirname "$target")"; then
    die "could not create target directory: $(dirname "$target")"
  fi
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    if ! ln -s "$source" "$target"; then
      die "could not install link: $target"
    fi
    created_targets[created_target_count]="$target"
    created_sources[created_target_count]="$source"
    created_target_count=$((created_target_count + 1))
  fi
  index=$((index + 1))
done

install_in_progress=0
trap - EXIT

printf 'Installed agent-neutral commands'
if [[ "$skill_dir_count" -gt 0 ]]; then
  printf ' and continuity skill adapters'
fi
printf '.\n'
