#!/usr/bin/env bash
# Push all DCS-related git repositories (packages monorepo + sibling app).
#
# Usage:
#   ./scripts/push-all.sh "your commit message"
#   ./scripts/push-all.sh                    # default timestamped message
#
# macOS / Linux:
#   chmod +x scripts/push-all.sh
#   ./scripts/push-all.sh "fix: cupps reconnect"
#
# Windows (Git Bash — installed with Git for Windows):
#   bash scripts/push-all.sh "fix: cupps reconnect"
#
# Optional environment overrides:
#   DCS_PACKAGES_DIR=/path/to/dcs-packages
#   DCS_APP_DIR=/path/to/dcs
#   DCS_GIT_BRANCH=main

set -euo pipefail

COMMIT_MSG="${1:-chore: sync DCS projects $(date -u +%Y-%m-%dT%H:%M:%SZ)}"
BRANCH="${DCS_GIT_BRANCH:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="${DCS_PACKAGES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
APP_DIR="${DCS_APP_DIR:-$(cd "$PACKAGES_DIR/.." && pwd)/dcs}"

push_repo() {
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

  if [[ -z "$(git status --porcelain)" ]]; then
    echo "No local changes to commit."
  else
    git add -A
    git commit -m "$COMMIT_MSG"
    echo "Committed changes."
  fi

  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" == "HEAD" ]]; then
    echo "Detached HEAD — cannot push branch. Checkout a branch first."
    return 1
  fi

  echo "Pushing to origin/$current_branch..."
  git push -u origin "$current_branch"
  echo "Done: $name"
}

echo "DCS push-all"
echo "Message: $COMMIT_MSG"
echo "Packages: $PACKAGES_DIR"
echo "App:      $APP_DIR"

push_repo "$PACKAGES_DIR" "dcs-packages"
push_repo "$APP_DIR" "dcs"

echo ""
echo "All repositories processed."
