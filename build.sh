#!/bin/bash
set -euo pipefail

PUSH="false"

usage() {
  cat <<EOF
Usage: ./publish.sh [--push]

Examples
  ./publish.sh        # build only (no push)
  ./publish.sh --push # build and push (with login)
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH="true"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 2;;
  esac
done


exec ./build-each.sh --variant workspace --emit-plain-tags true --push "${PUSH}" --login true

