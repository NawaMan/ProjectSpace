#!/bin/bash
set -euo pipefail

IMAGE_NAME="workspace-base"
CONTAINER_NAME="$IMAGE_NAME-run"

# Fixed workspace inside the container (do not change)
WORKSPACE="/home/coder/workspace"

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

SHELL_NAME="bash"

show_help() {
  cat <<'EOF'
Usage:
  start-container.sh [OPTIONS]                 # interactive shell
  start-container.sh [OPTIONS] -- <command...> # run a command then exit
  start-container.sh [OPTIONS] --daemon        # run container detached

Options:
  -b, --build    Force rebuild image before run
  -c, --clean    Remove container and image
  -d, --daemon   Run container detached (background)
  -h, --help     Show this help message

Notes:
  • Commands MUST follow a literal `--` (except --daemon).
  • You may pass raw `docker run` flags (beginning with '-') before `--`.
Examples:
  start-container.sh
  start-container.sh -- python -V
  start-container.sh --daemon
  start-container.sh -p 8888:8888 --daemon
EOF
}

DO_BUILD=false
DO_CLEAN=false
DAEMON=false
RUN_ARGS=()
CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build) DO_BUILD=true; shift ;;
    -c|--clean) DO_CLEAN=true; shift ;;
    -d|--daemon) DAEMON=true; shift ;;
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

if $DO_CLEAN; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker rmi "$IMAGE_NAME" 2>/dev/null || true
  exit 0
fi

if $DO_BUILD; then
  docker build -t "$IMAGE_NAME" .
fi

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
