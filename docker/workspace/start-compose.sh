#!/bin/bash
set -euo pipefail

# Make UID/GID available to docker-compose.yml
export HOST_UID="${HOST_UID:-$(id -u)}"
export HOST_GID="${HOST_GID:-$(id -g)}"

COMPOSE="docker compose"
SERVICE="app"

show_help() {
  cat <<EOF
Usage:
  $(basename "$0") [OPTIONS]                    # interactive one-off shell (bash)
  $(basename "$0") [OPTIONS] -- <command...>    # run a command then exit
  $(basename "$0") [OPTIONS] --daemon           # bring service up in background
  $(basename "$0") --attach                     # exec a bash shell into running service

Options:
  -b, --build            Build images before running
  -c, --clean            docker compose down --remove-orphans
      --prune            docker compose down --rmi local --volumes --remove-orphans
      --run-flags ...    Extra flags passed to 'docker compose run' (before --)
  -h, --help             Show this help message

Notes:
  • Commands MUST follow a literal '--' (except --daemon / --attach).
  • UID/GID are exported as HOST_UID / HOST_GID for docker-compose.yml.
  • One-off 'run' containers are removed on exit; --daemon uses 'up -d'.

Examples:
  $(basename "$0")                         # opens bash
  $(basename "$0") -- python -V           # runs a command then exits
  $(basename "$0") -- zsh                 # start zsh instead of bash
  $(basename "$0") --run-flags --service-ports -- jupyter lab --ip=0.0.0.0 --no-browser
  $(basename "$0") --daemon
  $(basename "$0") --attach
EOF
}

DO_BUILD=false
DO_CLEAN=false
DO_PRUNE=false
DO_DAEMON=false
DO_ATTACH=false
RUN_FLAGS=()
CMD=()

# Parse args (require -- before command)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  show_help; exit 0 ;;
    -r|--build) DO_BUILD=true; shift ;;
    -c|--clean) DO_CLEAN=true; shift ;;
    --prune)    DO_PRUNE=true; shift ;;
    --daemon)   DO_DAEMON=true; shift ;;
    --attach)   DO_ATTACH=true; shift ;;
    --run-flags)
      shift
      while [[ $# -gt 0 && "$1" != "--" ]]; do
        case "$1" in
          -h|--help|--daemon|--attach|-r|--build|-c|--clean|--prune|--run-flags)
            echo "Error: --run-flags must come before other options; or end with --" >&2
            exit 2
            ;;
          *)
            RUN_FLAGS+=("$1"); shift ;;
        esac
      done
      ;;
    --)
      shift
      CMD=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Tip: If you meant to run a command inside the container, use:" >&2
      echo "  $(basename "$0") -- <command...>" >&2
      exit 2
      ;;
    *)
      echo "Error: unrecognized argument: '$1'." >&2
      echo "Commands must follow a literal '--'." >&2
      exit 2
      ;;
  esac
done

# Validate incompatible combos
if $DO_DAEMON && ((${#CMD[@]} > 0)); then
  echo "Error: can't use --daemon and -- <command> together." >&2
  exit 2
fi
if $DO_ATTACH && ($DO_DAEMON || ((${#CMD[@]} > 0))); then
  echo "Error: --attach cannot be combined with --daemon or a one-off command." >&2
  exit 2
fi

# Clean / Prune / Build
$DO_PRUNE && exec $COMPOSE down --rmi local --volumes --remove-orphans
$DO_CLEAN && exec $COMPOSE down --remove-orphans
$DO_BUILD && $COMPOSE build

# Determine if service is up (container id if running)
APP_ID="$($COMPOSE ps -q "$SERVICE" || true)"

# Attach
if $DO_ATTACH; then
  if [[ -n "$APP_ID" ]]; then
    exec $COMPOSE exec "$SERVICE" bash
  else
    echo "Service '$SERVICE' is not running. Start it with --daemon first." >&2
    exit 2
  fi
fi

# Daemon mode
if $DO_DAEMON; then
  if [[ -n "$APP_ID" ]]; then
    echo "Service '$SERVICE' already running (container: $APP_ID)."
    exit 0
  fi
  exec $COMPOSE up -d "$SERVICE"
fi

# One-off run: interactive or command
if ((${#CMD[@]} == 0)); then
  # Interactive bash, container removed on exit
  exec $COMPOSE run --rm --no-deps "${RUN_FLAGS[@]}" "$SERVICE" bash
else
  # One-off command via bash -lc
  USER_CMD="${CMD[*]}"
  exec $COMPOSE run --rm --no-deps "${RUN_FLAGS[@]}" "$SERVICE" bash -lc "$USER_CMD"
fi
