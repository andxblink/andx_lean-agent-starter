#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$repo_root/tests/test-project.sh"
bash "$repo_root/tests/test-adopt.sh"
bash "$repo_root/tests/test-inspect.sh"
bash "$repo_root/tests/test-continuity.sh"
bash "$repo_root/tests/test-install.sh"
bash "$repo_root/tests/test-agent-contract.sh"
