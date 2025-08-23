#!/bin/bash
set -euo pipefail

###########################################################
# Script to build the workspace docker image for local run.
###########################################################


# ---------- Defaults ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-workspace:local}"

show_help() {
  cat <<'EOF'
Usage:
  build.sh [OPTIONS]

Builds the local Docker image and exits. No containers are run.

Options:
  -h, --help       Show this help message
  --image NAME     Override target image name (default: workspace:local)
  --no-cache       Build without using cache
  --pull           Always attempt to pull a newer base image
EOF
}

# --------- Parse CLI ---------
BUILD_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --image) shift; IMAGE_NAME="${1:?--image requires a name}"; shift || true ;;
    --no-cache|--pull) BUILD_ARGS+=("$1"); shift ;;
    -*) echo "Error: unrecognized option: '$1'"; echo "Try '$0 --help'."; exit 2 ;;
    *)  echo "Error: unrecognized argument: '$1'"; echo "Try '$0 --help'."; exit 2 ;;
  esac
done

# --------- Build local image only ---------
if [[ ! -f "${SCRIPT_DIR}/Dockerfile" ]]; then
  echo "Error: no Dockerfile found in ${SCRIPT_DIR}" >&2
  exit 1
fi

echo "Building local image: ${IMAGE_NAME}"
docker build -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}" "${BUILD_ARGS[@]}"

echo "Build complete: ${IMAGE_NAME}"
