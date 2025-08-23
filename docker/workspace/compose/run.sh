#!/bin/bash
set -euo pipefail

# Usage:
#   run.sh COMMAND ...

# Examples:
#   run.sh         # run a bash session
#   run.sh ls -la  # run a command (ls -la)

exec docker compose run --rm workspace "$@"
