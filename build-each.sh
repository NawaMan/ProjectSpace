#!/usr/bin/env bash
set -euo pipefail

# --- Defaults (override via flags or env) ---
IMAGE_NAME="${IMAGE_NAME:-nawaman/workspace}"

# VARIANT selects folder under ./docker/<variant> (e.g. workspace, notebook, ide)
VARIANT="${VARIANT:-workspace}"

# If --version not provided, we'll try to read from VERSION_FILE.
VERSION_TAG="${VERSION_TAG:-}"
VERSION_FILE="${VERSION_FILE:-version.txt}"

# Derived context & Dockerfile (can still be overridden by flags)
CONTEXT_DIR="${CONTEXT_DIR:-docker/${VARIANT}}"
DOCKERFILE="${DOCKERFILE:-docker/${VARIANT}/Dockerfile}"

PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"     # buildx targets
PUSH="${PUSH:-true}"                                  # true/false
USE_BUILDX="${USE_BUILDX:-true}"                      # true/false
LOGIN="${LOGIN:-false}"                               # true/false (uses env creds)
LATEST_ON_DEFAULT="${LATEST_ON_DEFAULT:-true}"        # true/false
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"              # used to decide 'latest'

# Also publish plain :latest and/or :<version> (DANGEROUS if multiple variants do this)
EMIT_PLAIN_TAGS="${EMIT_PLAIN_TAGS:-false}"

# Plain tag controls (used with --emit-plain-tags true)
PLAIN_INCLUDE_LATEST="${PLAIN_INCLUDE_LATEST:-true}"    # add :latest on default branch?
PLAIN_INCLUDE_CASCADE="${PLAIN_INCLUDE_CASCADE:-false}" # add :x.y and :x?

# Optional: read secrets from scripts if envs are unset
DOCKER_USER_SCRIPT="${DOCKER_USER_SCRIPT:-$HOME/secrets/.docker-user}"
DOCKER_PAT_SCRIPT="${DOCKER_PAT_SCRIPT:-$HOME/secrets/.docker-pat}"

# Build args accumulator
BUILD_ARGS=()

# --- Helpers ---
log()  { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build and (optionally) push a Docker image variant.

Options:
  --image NAME                Docker Hub image (default: ${IMAGE_NAME})
  --variant NAME              Variant folder under ./docker (default: ${VARIANT}) e.g. workspace|notebook|ide
  --version TAG               Version (e.g. 0.2.0). If omitted, reads from ${VERSION_FILE} when present.
  --version-file PATH         File to read version from (default: ${VERSION_FILE})

  --context DIR               Build context (default: ${CONTEXT_DIR})
  --file PATH                 Dockerfile path (default: ${DOCKERFILE})

  --push true|false           Push after build (default: ${PUSH})
  --buildx true|false         Use buildx multi-arch (default: ${USE_BUILDX})
  --platforms LIST            Platforms for buildx (default: ${PLATFORMS})
  --build-arg KEY=VAL         Repeatable; passes build args to Docker

  --login true|false          docker login using DOCKERHUB_USERNAME/DOCKERHUB_TOKEN (default: ${LOGIN})
  --latest-on-default t|f     Tag '<variant>-latest' if current branch == ${DEFAULT_BRANCH} (default: ${LATEST_ON_DEFAULT})
  --default-branch NAME       Default branch name (default: ${DEFAULT_BRANCH})

  --emit-plain-tags t|f       ALSO tag plain ':<version>' (always) and ':latest' (on default branch) (default: ${EMIT_PLAIN_TAGS})
  --plain-include-latest t|f  Include plain ':latest' when emitting plain tags (default: ${PLAIN_INCLUDE_LATEST})
  --plain-include-cascade t|f Include plain ':x.y' and ':x' when version is x.y.z (default: ${PLAIN_INCLUDE_CASCADE})

  -h, --help                  Show help

Environment variables respected:
  IMAGE_NAME, VARIANT, VERSION_TAG, VERSION_FILE, CONTEXT_DIR, DOCKERFILE,
  PUSH, USE_BUILDX, PLATFORMS, LOGIN,
  DOCKERHUB_USERNAME, DOCKERHUB_TOKEN,
  DOCKER_USER_SCRIPT, DOCKER_PAT_SCRIPT,
  LATEST_ON_DEFAULT, DEFAULT_BRANCH,
  EMIT_PLAIN_TAGS, PLAIN_INCLUDE_LATEST, PLAIN_INCLUDE_CASCADE
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE_NAME="$2"; shift 2;;
    --variant) VARIANT="$2"; shift 2;;
    --version) VERSION_TAG="$2"; shift 2;;
    --version-file) VERSION_FILE="$2"; shift 2;;

    --context) CONTEXT_DIR="$2"; shift 2;;
    --file) DOCKERFILE="$2"; shift 2;;

    --push) PUSH="$2"; shift 2;;
    --buildx) USE_BUILDX="$2"; shift 2;;
    --platforms) PLATFORMS="$2"; shift 2;;
    --build-arg) BUILD_ARGS+=( --build-arg "$2" ); shift 2;;

    --login) LOGIN="$2"; shift 2;;
    --latest-on-default) LATEST_ON_DEFAULT="$2"; shift 2;;
    --default-branch) DEFAULT_BRANCH="$2"; shift 2;;
    --emit-plain-tags) EMIT_PLAIN_TAGS="$2"; shift 2;;
    --plain-include-latest) PLAIN_INCLUDE_LATEST="$2"; shift 2;;
    --plain-include-cascade) PLAIN_INCLUDE_CASCADE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1 (use --help)";;
  esac
done

# Re-derive context & Dockerfile if the user changed VARIANT but not the paths explicitly.
# Only update if the user didn't override them via flags/env earlier.
if [[ ! -e "${CONTEXT_DIR}" || "${CONTEXT_DIR}" == "docker/"* ]]; then
  CONTEXT_DIR="docker/${VARIANT}"
fi
if [[ ! -f "${DOCKERFILE}" || "${DOCKERFILE}" == "docker/"*"/Dockerfile" ]]; then
  DOCKERFILE="docker/${VARIANT}/Dockerfile"
fi

# --- Resolve version ---
if [[ -z "${VERSION_TAG}" ]]; then
  if [[ -f "${VERSION_FILE}" ]]; then
    VERSION_TAG="$(tr -d ' \t\n\r' < "${VERSION_FILE}")"
    [[ -z "${VERSION_TAG}" ]] && die "Version file '${VERSION_FILE}' is empty."
  else
    die "No --version provided and '${VERSION_FILE}' not found."
  fi
fi

# --- Docker login (non-interactive) ---
if [[ "${LOGIN}" == "true" ]]; then
  # Auto-read from scripts if envs not present
  if [[ -z "${DOCKERHUB_USERNAME:-}" && -x "${DOCKER_USER_SCRIPT}" ]]; then
    DOCKERHUB_USERNAME="$("${DOCKER_USER_SCRIPT}")"
  fi
  if [[ -z "${DOCKERHUB_TOKEN:-}" && -x "${DOCKER_PAT_SCRIPT}" ]]; then
    DOCKERHUB_TOKEN="$("${DOCKER_PAT_SCRIPT}")"
  fi

  : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME or provide ${DOCKER_USER_SCRIPT}}"
  : "${DOCKERHUB_TOKEN:?Set DOCKERHUB_TOKEN or provide ${DOCKER_PAT_SCRIPT}}"

  log "Logging in to Docker Hub as ${DOCKERHUB_USERNAME}"
  echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin
fi

# --- Determine tags (variant-scoped + optional plain) ---
# Always tag variant-scoped: <image>:<variant>-<version>, and maybe <variant>-latest.
TAGS_ARG=( -t "${IMAGE_NAME}:${VARIANT}-${VERSION_TAG}" )

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [[ "${LATEST_ON_DEFAULT}" == "true" ]]; then
  if [[ "${CURRENT_BRANCH}" == "${DEFAULT_BRANCH}" || -z "${CURRENT_BRANCH}" ]]; then
    TAGS_ARG+=( -t "${IMAGE_NAME}:${VARIANT}-latest" )
  fi
fi

# Optionally add plain tags (DANGEROUS if multiple variants push them)
if [[ "${EMIT_PLAIN_TAGS}" == "true" ]]; then
  # always include exact :<version>
  TAGS_ARG+=( -t "${IMAGE_NAME}:${VERSION_TAG}" )

  # add :latest only on default branch (or outside git) if allowed
  if [[ "${PLAIN_INCLUDE_LATEST}" == "true" && "${LATEST_ON_DEFAULT}" == "true" && ( "${CURRENT_BRANCH}" == "${DEFAULT_BRANCH}" || -z "${CURRENT_BRANCH}" ) ]]; then
    TAGS_ARG+=( -t "${IMAGE_NAME}:latest" )
  fi

  # optionally add cascades :x.y and :x if version is x.y.z
  if [[ "${PLAIN_INCLUDE_CASCADE}" == "true" && "${VERSION_TAG}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"; MINOR="${BASH_REMATCH[2]}"
    TAGS_ARG+=( -t "${IMAGE_NAME}:${MAJOR}.${MINOR}" -t "${IMAGE_NAME}:${MAJOR}" )
  fi
fi

log "Image:      ${IMAGE_NAME}"
log "Variant:    ${VARIANT}"
log "Version:    ${VERSION_TAG}"
log "Context:    ${CONTEXT_DIR}"
log "Dockerfile: ${DOCKERFILE}"
log "Platforms:  ${PLATFORMS}"
log "Tags:       ${TAGS_ARG[*]//-t /}"

# --- Sanity checks ---
[[ -d "${CONTEXT_DIR}" ]] || die "Context dir not found: ${CONTEXT_DIR}"
[[ -f "${DOCKERFILE}" ]]  || die "Dockerfile not found: ${DOCKERFILE}"

# --- Build / Push ---
if [[ "${USE_BUILDX}" == "true" ]]; then
  log "Setting up buildx (multi-arch: ${PLATFORMS})"
  docker buildx create --use --name ci_builder >/dev/null 2>&1 || docker buildx use ci_builder
  docker buildx inspect --bootstrap >/dev/null

  # Decide platforms based on push/load to avoid manifest-list load error
  HOST_PLATFORM="$(docker version -f '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null || echo 'linux/amd64')"
  if [[ "${PUSH}" == "true" ]]; then
    EFFECTIVE_PLATFORMS="${PLATFORMS}"
  else
    EFFECTIVE_PLATFORMS="${HOST_PLATFORM}"
    log "Build-only mode: restricting platforms to ${EFFECTIVE_PLATFORMS} (--load can't import manifest lists)"
  fi

  log "Building with buildx"
  docker buildx build \
    --platform "${EFFECTIVE_PLATFORMS}" \
    -f "${DOCKERFILE}" \
    "${BUILD_ARGS[@]}" \
    "${TAGS_ARG[@]}" \
    "${CONTEXT_DIR}" \
    $( [[ "${PUSH}" == "true" ]] && echo "--push" || echo "--load" )
else
  log "Building with classic docker build"
  docker build -f "${DOCKERFILE}" \
    "${BUILD_ARGS[@]}" \
    "${TAGS_ARG[@]}" \
    "${CONTEXT_DIR}"
  if [[ "${PUSH}" == "true" ]]; then
    for t in "${TAGS_ARG[@]}"; do
      tag="${t##-t }"
      log "Pushing ${tag}"
      docker push "${tag}"
    done
  fi
fi

log "Done."
