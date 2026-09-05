#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    return 1
  fi
}

require yamllint
require kustomize
require kubeconform

# Lint YAML (including Kustomize and Flux manifests)
(
  cd "$ROOT_DIR"
  yamllint -c .yamllint.yaml .
)

# Render and validate all cluster manifests
# Pipe to stdin: kubeconform skips files without a recognized extension,
# so a plain mktemp file would silently validate nothing.
kustomize build "$ROOT_DIR/clusters/prod" | kubeconform \
  -strict \
  -ignore-missing-schemas \
  -summary \
  -
