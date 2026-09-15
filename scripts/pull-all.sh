#!/usr/bin/env bash
# Pull latest for all DCS-related git repositories (packages monorepo + sibling app).
#
# Usage:
#   ./scripts/pull-all.sh
#
# Windows (Git Bash — do NOT use plain "bash"; that launches WSL):
#   .\scripts\pull-all.bat
#
# Optional environment overrides:
#   DCS_PACKAGES_DIR=/path/to/dcs-packages
#   DCS_APP_DIR=/path/to/dcs
#   DCS_GIT_BRANCH=main

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="${DCS_PACKAGES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
APP_DIR="${DCS_APP_DIR:-$(cd "$PACKAGES_DIR/.." && pwd)/dcs}"
PREFERRED_BRANCH="${DCS_GIT_BRANCH:-}"

pull_repo() {
  local dir="$1"
  local name="$2"

  if [[ ! -d "$dir" ]]; then
    echo "[skip] $name — directory not found: $dir"
    return 0
  fi

  if [[ ! -d "$dir/.git" ]]; then
    echo "[skip] $name — not a git repository: $dir"
    return 0
  fi

  echo ""
  echo "=== $name ($dir) ==="
  cd "$dir"

  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" == "HEAD" ]]; then
    echo "Detached HEAD — checkout a branch before pulling."
    return 1
  fi

  if [[ -n "$PREFERRED_BRANCH" && "$current_branch" != "$PREFERRED_BRANCH" ]]; then
    echo "Current branch is $current_branch (preferred: $PREFERRED_BRANCH)."
  fi

  echo "Fetching origin..."
  git fetch origin

  echo "Pulling origin/$current_branch..."
  git pull --ff-only origin "$current_branch"

  if [[ -f melos.yaml ]] && command -v melos >/dev/null 2>&1; then
    echo "Running melos bootstrap..."
    melos bootstrap || echo "melos bootstrap failed (continuing)"
  fi

  if [[ -f pubspec.yaml ]] && command -v flutter >/dev/null 2>&1; then
    if grep -q "flutter:" pubspec.yaml 2>/dev/null; then
      echo "Running flutter pub get..."
      flutter pub get || echo "flutter pub get failed (continuing)"
    fi
  fi

  echo "Done: $name"
}

echo "DCS pull-all"
echo "Packages: $PACKAGES_DIR"
echo "App:      $APP_DIR"

pull_repo "$PACKAGES_DIR" "dcs-packages"
pull_repo "$APP_DIR" "dcs"

echo ""
echo "All repositories pulled."
