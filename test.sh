#!/bin/bash
set -euo pipefail

# Define cleanup
cleanup() {
  rm -f in-workspace.txt in-host.txt
}
trap cleanup EXIT  # run cleanup on script exit (success or error)

cleanup
./run-workspace.sh -- date | tee in-workspace.txt > in-host.txt

if diff -u in-workspace.txt in-host.txt; then
  echo "✅ Files match"
else
  echo "❌ Files differ"
  exit 1
fi