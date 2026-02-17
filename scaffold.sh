#!/usr/bin/env bash
set -euo pipefail

# scaffold.sh — Copy and customize deploy templates into a target project.
#
# Usage:
#   scaffold.sh --target /path/to/project --name my-app --ecr-repo 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app --stack python [--force]
#   scaffold.sh --target /path/to/project --name my-app --ecr-repo 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app --stack node [--force]
#   scaffold.sh --target /path/to/project --name my-app --ecr-repo 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app  # auto-detects stack
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
    -e "s|__ECR_REPO__|${ECR_REPO}|g" \
    -e "s|__RUNTIME_ENV_KEY__|${RUNTIME_ENV_KEY}|g" \
    -e "s|__RUNTIME_ENV_VALUE__|${RUNTIME_ENV_VALUE}|g" \
    -e "s|__EB_APP_NAME__|${EB_APP_NAME}|g" \
    -e "s|__EB_ENV_NAME__|${EB_ENV_NAME}|g" \
    -e "s|__AWS_REGION__|${AWS_REGION}|g" \
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
Usage: scaffold.sh --target <dir> --name <name> --ecr-repo <account.dkr.ecr.region.amazonaws.com/repo> [--region us-east-1] [--eb-app name] [--eb-env name] [--stack python|node] [--force]

Options:
  --target    Target project directory (required)
  --name      Primary service name (used in docker-compose.yml) (required)
  --ecr-repo  Full ECR repo URI (required)
  --region    AWS region for Elastic Beanstalk defaults (default: us-east-1)
  --eb-app    Optional EB application name (default: --name)
  --eb-env    Optional EB environment name (default: <name>-env)
  --stack     python or node (auto-detected if omitted)
  --force     Overwrite existing files
EOF
  exit 1
}

# ─── Parse arguments ─────────────────────────────────────────────────────────

TARGET=""
SERVICE_NAME=""
ECR_REPO=""
STACK=""
FORCE="false"
AWS_REGION="us-east-1"
EB_APP_NAME=""
EB_ENV_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --name)    SERVICE_NAME="$2"; shift 2 ;;
    --ecr-repo) ECR_REPO="$2"; shift 2 ;;
    --region) AWS_REGION="$2"; shift 2 ;;
    --eb-app) EB_APP_NAME="$2"; shift 2 ;;
    --eb-env) EB_ENV_NAME="$2"; shift 2 ;;
    --stack)   STACK="$2"; shift 2 ;;
    --force)   FORCE="true"; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$TARGET" ]]       || die "--target is required"
[[ -d "$TARGET" ]]       || die "Target directory does not exist: $TARGET"
[[ -n "$SERVICE_NAME" ]] || die "--name is required"
[[ -n "$ECR_REPO" ]]    || die "--ecr-repo is required (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app)"

if [[ -z "$STACK" ]]; then
  STACK=$(detect_stack "$TARGET")
  info "auto-detected stack: $STACK"
fi

case "$STACK" in
  python)
    PORT="8000"
    RUNTIME_ENV_KEY="FLASK_ENV"
    RUNTIME_ENV_VALUE="production"
    ;;
  node)
    PORT="3000"
    RUNTIME_ENV_KEY="NODE_ENV"
    RUNTIME_ENV_VALUE="production"
    ;;
  *) die "Unknown stack: $STACK (must be python or node)" ;;
esac

if [[ -z "$EB_APP_NAME" ]]; then
  EB_APP_NAME="$SERVICE_NAME"
fi
if [[ -z "$EB_ENV_NAME" ]]; then
  EB_ENV_NAME="${SERVICE_NAME}-env"
fi

# ─── Scaffold files ─────────────────────────────────────────────────────────

CREATED_FILES=()

# Dockerfile
copy_if_missing "$TEMPLATES_DIR/Dockerfile.${STACK}" "$TARGET/Dockerfile"

# docker-compose.yml
render_template "$TEMPLATES_DIR/docker-compose.yml.tmpl" "$TARGET/docker-compose.yml"

# .elasticbeanstalk/config.yml
render_template "$TEMPLATES_DIR/.elasticbeanstalk/config.yml.tmpl" "$TARGET/.elasticbeanstalk/config.yml"

# GitHub Actions workflow
copy_if_missing "$TEMPLATES_DIR/.github/workflows/elastic-beanstalk-deploy.yml" "$TARGET/.github/workflows/elastic-beanstalk-deploy.yml"

# .dockerignore
copy_if_missing "$TEMPLATES_DIR/.dockerignore" "$TARGET/.dockerignore"

# .env.example (stack-specific)
copy_if_missing "$TEMPLATES_DIR/.env.example.${STACK}" "$TARGET/.env.example"

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
