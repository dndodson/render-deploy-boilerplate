#!/usr/bin/env bash
set -euo pipefail

# scaffold.sh — Copy and customize deploy templates into a target project.
#
# Usage:
#   scaffold.sh --target /path/to/project --name my-app --gh-repo org/repo --stack python [--force]
#   scaffold.sh --target /path/to/project --name my-app --gh-repo org/repo --stack node [--force]
#   scaffold.sh --target /path/to/project --name my-app --gh-repo org/repo  # auto-detects stack
#
# Templates are resolved relative to this script's location.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# ─── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "scaffold: error: $1" >&2; exit 1; }
info() { echo "scaffold: $1" >&2; }

copy_if_missing() {
  local src="$1" dest="$2"
  if [[ -f "$dest" && "$FORCE" != "true" ]]; then
    info "skip (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  info "created: $dest"
  CREATED_FILES+=("$dest")
}

render_template() {
  local src="$1" dest="$2"
  if [[ -f "$dest" && "$FORCE" != "true" ]]; then
    info "skip (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|__SERVICE_NAME__|${SERVICE_NAME}|g" \
    -e "s|__PORT__|${PORT}|g" \
    -e "s|__GH_REPO__|${GH_REPO}|g" \
    "$src" > "$dest"
  info "created: $dest"
  CREATED_FILES+=("$dest")
}

detect_stack() {
  local target="$1"
  if [[ -f "$target/requirements.txt" || -f "$target/pyproject.toml" || -f "$target/Pipfile" ]]; then
    echo "python"
  elif [[ -f "$target/package.json" ]]; then
    echo "node"
  else
    echo "python"
  fi
}

usage() {
  cat <<'EOF'
Usage: scaffold.sh --target <dir> --name <name> --gh-repo <owner/repo> [--stack python|node] [--force]

Options:
  --target    Target project directory (required)
  --name      Service name for render.yaml (required)
  --gh-repo   GitHub owner/repo for ghcr.io image URL (required)
  --stack     python or node (auto-detected if omitted)
  --force     Overwrite existing files
EOF
  exit 1
}

# ─── Parse arguments ─────────────────────────────────────────────────────────

TARGET=""
SERVICE_NAME=""
GH_REPO=""
STACK=""
FORCE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --name)    SERVICE_NAME="$2"; shift 2 ;;
    --gh-repo) GH_REPO="$2"; shift 2 ;;
    --stack)   STACK="$2"; shift 2 ;;
    --force)   FORCE="true"; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$TARGET" ]]       || die "--target is required"
[[ -d "$TARGET" ]]       || die "Target directory does not exist: $TARGET"
[[ -n "$SERVICE_NAME" ]] || die "--name is required"
[[ -n "$GH_REPO" ]]     || die "--gh-repo is required (e.g. climatecentral-ai/my-app)"

if [[ -z "$STACK" ]]; then
  STACK=$(detect_stack "$TARGET")
  info "auto-detected stack: $STACK"
fi

case "$STACK" in
  python) PORT="8000" ;;
  node)   PORT="3000" ;;
  *) die "Unknown stack: $STACK (must be python or node)" ;;
esac

# ─── Scaffold files ─────────────────────────────────────────────────────────

CREATED_FILES=()

# Dockerfile
copy_if_missing "$TEMPLATES_DIR/Dockerfile.${STACK}" "$TARGET/Dockerfile"

# render.yaml (templated)
render_template "$TEMPLATES_DIR/render.yaml.tmpl" "$TARGET/render.yaml"

# GitHub Actions workflow
copy_if_missing "$TEMPLATES_DIR/.github/workflows/render-deploy.yml" "$TARGET/.github/workflows/render-deploy.yml"

# .dockerignore
copy_if_missing "$TEMPLATES_DIR/.dockerignore" "$TARGET/.dockerignore"

# .env.example
copy_if_missing "$TEMPLATES_DIR/.env.example" "$TARGET/.env.example"

# ─── Output ──────────────────────────────────────────────────────────────────

info "scaffold complete (stack=$STACK, files=${#CREATED_FILES[@]})"

# JSON output for programmatic consumption
echo "{"
echo "  \"ok\": true,"
echo "  \"stack\": \"$STACK\","
echo "  \"port\": \"$PORT\","
echo "  \"service_name\": \"$SERVICE_NAME\","
echo "  \"files_created\": ${#CREATED_FILES[@]},"
echo "  \"files\": ["
for i in "${!CREATED_FILES[@]}"; do
  if [[ $i -lt $((${#CREATED_FILES[@]} - 1)) ]]; then
    echo "    \"${CREATED_FILES[$i]}\","
  else
    echo "    \"${CREATED_FILES[$i]}\""
  fi
done
echo "  ]"
echo "}"
