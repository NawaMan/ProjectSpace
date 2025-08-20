#!/bin/bash
set -euo pipefail

# ---------- Defaults (tweak as you like) ----------

# Base repo (no variant in the path; variant lives in the tag)
IMAGE_REPO_DEFAULT="nawaman/workspace"

# Default variant (folder under ./docker and prefix in tag)
VARIANT_DEFAULT="workspace"

# Default version (overridden by version.txt or --version)
VERSION_DEFAULT="latest"

# Public knobs (overridable via env/flags)
IMAGE_REPO="${IMAGE_REPO:-${IMAGE_REPO_DEFAULT}}"
VARIANT="${VARIANT:-${VARIANT_DEFAULT}}"
VERSION_TAG="${VERSION_TAG:-${VERSION_DEFAULT}}"

# Compose the image tag as <variant>-<version> (back-compat shim ensures IMAGE_TAG always exists)
IMAGE_TAG="${IMAGE_TAG:-${VARIANT}-${VERSION_TAG}}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

# Container name when running locally
CONTAINER_NAME="${CONTAINER_NAME:-${VARIANT}-run}"

# Fixed workspace inside the container (do not change)
WORKSPACE="/home/coder/workspace"

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
SHELL_NAME="bash"

# Flags
DO_BUILD=false
DO_CLEAN=false
DO_PULL=false
DAEMON=false
RUN_ARGS=()
CMD=()

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Assume Dockerfile is next to this script by default (override with --dockerfile)
DOCKERFILE_DIR="${DOCKERFILE_DIR:-${SCRIPT_DIR}}"


show_help() {
  cat <<'EOF'
Usage:
  start-container.sh [OPTIONS]                 # interactive shell
  start-container.sh [OPTIONS] -- <command...> # run a command then exit
  start-container.sh [OPTIONS] --daemon        # run container detached

Options:
  -b, --build               Build image from local Dockerfile (if present)
  -c, --clean               Remove container (and local image if present)
  -d, --daemon              Run container detached (background)
      --pull                Force docker pull (refresh image from registry)

      --image <name>        Image repo/name       (default: nawaman/workspace)
      --variant <name>      Variant prefix        (default: workspace)
      --version <tag>       Version suffix        (default: latest)
      --tag <tag>           (Deprecated) alias for --version (final tag becomes <variant>-<tag>)
      --dockerfile <dir>    Directory containing Dockerfile (default: alongside script)

  -h, --help                Show this help message

Notes:
  • Final image ref is: <image>/<repo>:<variant>-<version>
    e.g. nawaman/workspace:workspace-0.1.0
  • Commands MUST follow a literal `--` (except --daemon).
  • You may pass raw `docker run` flags (beginning with '-') before `--'.

Examples:
  start-container.sh
  start-container.sh -- python -V
  start-container.sh --daemon
  start-container.sh --image nawaman/workspace --variant workspace --version 0.1.0
  start-container.sh -p 8888:8888 --daemon
  start-container.sh --build --dockerfile ./docker/workspace
EOF
}

# --------- Parse CLI ---------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build) DO_BUILD=true; shift ;;
    -c|--clean) DO_CLEAN=true; shift ;;
    -d|--daemon) DAEMON=true; shift ;;
    --pull) DO_PULL=true; shift ;;

    --image) IMAGE_REPO="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --version) VERSION_TAG="$2"; shift 2 ;;
    # Back-compat: --tag is treated as "version", final tag stays <variant>-<version>
    --tag) VERSION_TAG="$2"; shift 2 ;;

    --dockerfile) DOCKERFILE_DIR="$2"; shift 2 ;;
    -h|--help)  show_help; exit 0 ;;
    --)         shift; CMD=("$@"); break ;;
    -* )        RUN_ARGS+=("$1"); shift ;;
    *  )
      echo "Error: unrecognized argument: '$1'"
      echo "If you intended to run a command inside the container, use:"
      echo "  $0 -- <command...>"
      echo "Or to run detached, use:"
      echo "  $0 --daemon"
      echo "Try '$0 --help' for usage."
      exit 2
      ;;
  esac
done

# Recompute IMAGE_TAG/IMAGE_NAME from (possibly) updated VARIANT/VERSION_TAG/IMAGE_REPO
IMAGE_TAG="${VARIANT}-${VERSION_TAG}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

# --------- Actions ---------
if $DO_CLEAN; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    docker rmi "$IMAGE_NAME" || true
  fi
  exit 0
fi

# Build if asked (and Dockerfile exists)
if $DO_BUILD; then
  if [[ -f "${DOCKERFILE_DIR}/Dockerfile" ]]; then
    echo "Building ${IMAGE_NAME} from ${DOCKERFILE_DIR}/Dockerfile"
    docker build -t "$IMAGE_NAME" -f "${DOCKERFILE_DIR}/Dockerfile" "${DOCKERFILE_DIR}"
  else
    echo "Warning: Dockerfile not found in '${DOCKERFILE_DIR}'. Skipping build."
  fi
fi

# Pull if asked or if image missing
if $DO_PULL || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Pulling image: $IMAGE_NAME"
  docker pull "$IMAGE_NAME"
fi

# Ensure previous container (same name) isn’t hanging around
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

TTY_ARGS="-i"
if [ -t 1 ]; then
  TTY_ARGS="-it"
fi

COMMON_ARGS=(
  --name "$CONTAINER_NAME"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -v "$PWD":"$WORKSPACE"
)

if $DAEMON; then
  # Daemon mode (detached)
  exec docker run -d \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "while true; do sleep 3600; done"
elif [[ ${#CMD[@]} -eq 0 ]]; then
  # Interactive shell
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME"
else
  # One-off command
  USER_CMD="${CMD[*]}"
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "$USER_CMD"
fi
