#!/bin/bash
set -euo pipefail

# ---------- Defaults ----------
IMAGE_REPO_DEFAULT="nawaman/workspace"
VARIANT_DEFAULT="workspace"
VERSION_DEFAULT="latest"

IMAGE_REPO="${IMAGE_REPO:-${IMAGE_REPO_DEFAULT}}"
VARIANT="${VARIANT:-${VARIANT_DEFAULT}}"
VERSION_TAG="${VERSION_TAG:-${VERSION_DEFAULT}}"

IMAGE_TAG="${IMAGE_TAG:-${VARIANT}-${VERSION_TAG}}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

CONTAINER_NAME="${CONTAINER_NAME:-${VARIANT}-run}"
WORKSPACE="/home/coder/workspace"

# Respect overrides like docker-compose does, else detect host values
HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"

SHELL_NAME="bash"

DO_PULL=false
DAEMON=false
RUN_ARGS=()
CMD=()

show_help() {
  cat <<'EOF'
Starting a workspace container.

Usage:
  start-workspace.sh [OPTIONS]                 # interactive shell
  start-workspace.sh [OPTIONS] -- <command...> # run a command then exit
  start-workspace.sh [OPTIONS] --daemon        # run container detached

Options:
  -d, --daemon            Run container detached (background)
      --pull              Pull/refresh the image from registry (also pulls if image missing)

      --image   <name>    Image repo/name       (default: nawaman/workspace)
      --variant <name>    Variant prefix        (default: workspace)
      --version <tag>     Version suffix        (default: latest)
      --tag     <tag>     Alias for --version (final tag is <variant>-<version>)
      --name    <name>    Container name        (default: <variant>-run)

  -h, --help              Show this help message

Notes:
  • Final image ref: <repo>:<variant>-<version>, e.g. nawaman/workspace:workspace-latest
  • Bind: . -> /home/coder/workspace; Working dir: /home/coder/workspace
  • HOST_UID/HOST_GID can be exported before running to override detected values.
EOF
}

# --------- Parse CLI ---------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--daemon) DAEMON=true;         shift   ;;
    --pull)      DO_PULL=true;        shift   ;;
    --image)     IMAGE_REPO="$2";     shift 2 ;;
    --variant)   VARIANT="$2";        shift 2 ;;
    --version)   VERSION_TAG="$2";    shift 2 ;;
    --tag)       VERSION_TAG="$2";    shift 2 ;;
    --name)      CONTAINER_NAME="$2"; shift 2 ;;
    -h|--help)   show_help;        exit 0  ;;
    --) shift; CMD=("$@"); break ;;
    -*) RUN_ARGS+=("$1");  shift ;;
    *)  echo "Error: unrecognized argument: '$1'"; echo "Use '--' before commands. Try '$0 --help'."; exit 2 ;;
  esac
done

IMAGE_TAG="${VARIANT}-${VERSION_TAG}"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"
CONTAINER_NAME="${CONTAINER_NAME:-${VARIANT}-run}"

# --------- Pull if requested or missing ---------
if $DO_PULL || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Pulling image: $IMAGE_NAME"
  docker pull "$IMAGE_NAME" || { echo "Error: failed to pull '$IMAGE_NAME'." >&2; exit 1; }
fi

# Final check
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Error: image '$IMAGE_NAME' not available locally. Try '--pull'." >&2
  exit 1
fi

# Clean up any previous container with the same name
docker rm -f "$CONTAINER_NAME" &>/dev/null || true

TTY_ARGS="-i"
if [ -t 1 ]; then TTY_ARGS="-it"; fi

COMMON_ARGS=(
  --name "$CONTAINER_NAME"
  -e HOST_UID="$HOST_UID"
  -e HOST_GID="$HOST_GID"
  -v "$PWD":"$WORKSPACE"
  -w "$WORKSPACE"
)

if $DAEMON; then
  exec docker run -d \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "while true; do sleep 3600; done"
  
elif [[ ${#CMD[@]} -eq 0 ]]; then
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME"

else
  USER_CMD="${CMD[*]}"
  exec docker run --rm $TTY_ARGS \
    "${COMMON_ARGS[@]}" \
    "${RUN_ARGS[@]}" \
    "$IMAGE_NAME" \
    "$SHELL_NAME" -lc "$USER_CMD"
fi
