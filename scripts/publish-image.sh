#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build and publish the BrowserBox container image.

Defaults:
  GitHub image:     ghcr.io/browserbox/browserbox
  Docker Hub image: dosaygo/browserbox
  Platform:         linux/amd64

Auth prerequisites:
  The script logs into enabled target registries before publishing.
  GitHub Container Registry:
    GHCR_USERNAME/GITHUB_ACTOR plus GHCR_TOKEN/GITHUB_TOKEN, or docker login ghcr.io.
  Docker Hub:
    docker login, or DOCKERHUB_USERNAME plus DOCKERHUB_TOKEN/DOCKERHUB_PASSWORD.
  GCR/Artifact Registry:
    gcloud auth login, GCR_ACCESS_TOKEN, GCR_JSON_KEY, or GCR_USERNAME plus GCR_PASSWORD.

Common usage:
  scripts/publish-image.sh
  BROWSERBOX_RELEASE_TAG=v16.8.11 scripts/publish-image.sh
  DRY_RUN=1 scripts/publish-image.sh

Environment overrides:
  GHCR_IMAGE                 Full GitHub Container Registry image ref. Empty string disables GHCR.
  DOCKERHUB_IMAGE            Full Docker Hub image ref. Empty string disables Docker Hub.
  GCR_IMAGE                  Full GCR image ref. Default: disabled.
  GHCR_IMAGE_NAME            GHCR image path used by default. Default: browserbox/browserbox
  DOCKERHUB_IMAGE_NAME       Docker Hub image path used by default. Default: dosaygo/browserbox
  BROWSERBOX_RELEASE_TAG     BrowserBox release to install. Default: latest GitHub release.
  PLATFORMS                  Buildx platforms. Default: linux/amd64
  PUSH_LATEST                Also tag latest. Default: true
  TAG_WITHOUT_V              For vX.Y.Z tags, also push X.Y.Z. Default: true
  TAG_GIT_SHA                Also tag sha-<short-sha>. Default: false
  EXTRA_TAGS                 Comma-separated additional tags.
  PIN_RELEASE                Pass BROWSERBOX_RELEASE_TAG to Dockerfile. Default: true
  SBOM                       Add buildx --sbom=true. Default: false
  PROVENANCE                 Add buildx --provenance=true. Default: false
  SKIP_REGISTRY_LOGIN        Do not run registry login preflight. Default: false
  DRY_RUN                    Print the buildx command without running it.
USAGE
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[publish] ERROR: required command not found: $1" >&2
    exit 127
  fi
}

normalize_ref() {
  local ref lower
  ref="$1"
  lower="$(printf '%s' "$ref" | tr '[:upper:]' '[:lower:]')"
  if [[ "$ref" != "$lower" ]]; then
    echo "[publish] normalizing image ref to lowercase: ${ref} -> ${lower}" >&2
  fi
  printf '%s' "$lower"
}

latest_browserbox_release() {
  local tag
  tag="$(
    curl -fsSL "https://api.github.com/repos/BrowserBox/BrowserBox/releases/latest" \
      | sed -nE 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
      | head -n 1
  )"

  if [[ -z "$tag" ]]; then
    echo "[publish] ERROR: could not resolve the latest BrowserBox release tag." >&2
    exit 1
  fi

  printf '%s\n' "$tag"
}

print_command() {
  local arg
  printf '[publish] '
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

registry_for_ref() {
  local ref first
  ref="$1"

  if [[ "$ref" != */* ]]; then
    printf 'docker.io\n'
    return 0
  fi

  first="${ref%%/*}"

  if [[ "$first" == *.* || "$first" == *:* || "$first" == "localhost" ]]; then
    case "$first" in
      index.docker.io|registry-1.docker.io) printf 'docker.io\n' ;;
      *) printf '%s\n' "$first" ;;
    esac
    return 0
  fi

  printf 'docker.io\n'
}

add_unique() {
  local item existing
  item="$1"
  shift

  for existing in "$@"; do
    if [[ "$existing" == "$item" ]]; then
      return 1
    fi
  done

  printf '%s\n' "$item"
}

docker_login_with_password() {
  local registry username password
  registry="$1"
  username="$2"
  password="$3"

  if [[ "$registry" == "docker.io" ]]; then
    printf '%s' "$password" | docker login --username "$username" --password-stdin
  else
    printf '%s' "$password" | docker login "$registry" --username "$username" --password-stdin
  fi
}

login_dockerhub() {
  local username password
  username="${DOCKERHUB_USERNAME:-${DOCKER_USERNAME:-}}"
  password="${DOCKERHUB_TOKEN:-${DOCKERHUB_PASSWORD:-${DOCKER_PASSWORD:-}}}"

  echo "[publish] Logging into Docker Hub"
  if [[ -n "$username" && -n "$password" ]]; then
    docker_login_with_password docker.io "$username" "$password"
  else
    docker login
  fi
}

login_gcr() {
  local registry username password account project
  registry="$1"
  username="${GCR_USERNAME:-}"
  password="${GCR_PASSWORD:-${GCR_ACCESS_TOKEN:-${GCR_JSON_KEY:-}}}"

  if [[ -z "$username" && -n "${GCR_ACCESS_TOKEN:-}" ]]; then
    username="oauth2accesstoken"
  elif [[ -z "$username" && -n "${GCR_JSON_KEY:-}" ]]; then
    username="_json_key"
  fi

  echo "[publish] Logging into ${registry}"
  if [[ -n "$username" && -n "$password" ]]; then
    docker_login_with_password "$registry" "$username" "$password"
    return 0
  fi

  if command -v gcloud >/dev/null 2>&1; then
    gcloud auth configure-docker "$registry" --quiet
    gcloud auth print-access-token --quiet >/dev/null
    account="$(gcloud config get-value account 2>/dev/null || true)"
    project="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ -n "$account" ]]; then
      echo "[publish] gcloud account: ${account}"
    fi
    if [[ -n "$project" ]]; then
      echo "[publish] gcloud project: ${project}"
    fi
    return 0
  fi

  docker login "$registry"
}

login_ghcr() {
  local username password
  username="${GHCR_USERNAME:-${GITHUB_ACTOR:-}}"
  password="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"

  echo "[publish] Logging into ghcr.io"
  if [[ -n "$username" && -n "$password" ]]; then
    docker_login_with_password ghcr.io "$username" "$password"
  else
    docker login ghcr.io
  fi
}

login_registry() {
  local registry
  registry="$1"

  case "$registry" in
    docker.io) login_dockerhub ;;
    ghcr.io) login_ghcr ;;
    gcr.io|*.gcr.io|*.pkg.dev) login_gcr "$registry" ;;
    *)
      echo "[publish] Logging into ${registry}"
      docker login "$registry"
      ;;
  esac
}

login_target_registries() {
  local registries=()
  local image registry added

  for image in "$@"; do
    registry="$(registry_for_ref "$image")"
    added="$(add_unique "$registry" "${registries[@]}")" || true
    if [[ -n "$added" ]]; then
      registries+=("$added")
    fi
  done

  echo "[publish] Registry login preflight:"
  for registry in "${registries[@]}"; do
    login_registry "$registry"
  done
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need docker
need curl
need git
need sed
need tr

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${DOCKERFILE:-${ROOT}/Dockerfile}"
GHCR_IMAGE_NAME="${GHCR_IMAGE_NAME:-${IMAGE_NAME:-browserbox/browserbox}}"
DOCKERHUB_IMAGE_NAME="${DOCKERHUB_IMAGE_NAME:-dosaygo/browserbox}"
GHCR_IMAGE="${GHCR_IMAGE-ghcr.io/${GHCR_IMAGE_NAME}}"
DOCKERHUB_IMAGE="${DOCKERHUB_IMAGE-${DOCKERHUB_IMAGE_NAME}}"
GCR_IMAGE="${GCR_IMAGE-}"
PLATFORMS="${PLATFORMS:-linux/amd64}"

release_tag="${BROWSERBOX_RELEASE_TAG:-${BBX_RELEASE_TAG:-}}"
if [[ -z "$release_tag" || "$release_tag" == "latest" ]]; then
  release_tag="$(latest_browserbox_release)"
fi

created="${OCI_IMAGE_CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
revision="${OCI_IMAGE_REVISION:-$(git -C "$ROOT" rev-parse HEAD)}"
short_revision="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
source_url="${OCI_IMAGE_SOURCE:-https://github.com/BrowserBox/browserbox-action}"
documentation_url="${OCI_IMAGE_DOCUMENTATION:-https://github.com/BrowserBox/browserbox-action#readme}"

images=()
if [[ -n "$GHCR_IMAGE" ]]; then
  images+=("$(normalize_ref "$GHCR_IMAGE")")
fi
if [[ -n "$DOCKERHUB_IMAGE" ]]; then
  images+=("$(normalize_ref "$DOCKERHUB_IMAGE")")
fi
if [[ -n "$GCR_IMAGE" ]]; then
  images+=("$(normalize_ref "$GCR_IMAGE")")
fi

if [[ "${#images[@]}" -eq 0 ]]; then
  echo "[publish] ERROR: no target images configured." >&2
  exit 2
fi

tag_args=()
add_tag() {
  local tag image
  tag="$1"
  [[ -n "$tag" ]] || return 0

  for image in "${images[@]}"; do
    tag_args+=(--tag "${image}:${tag}")
  done
}

add_tag "$release_tag"

if is_truthy "${TAG_WITHOUT_V:-true}" && [[ "$release_tag" == v* ]]; then
  add_tag "${release_tag#v}"
fi

if is_truthy "${PUSH_LATEST:-true}"; then
  add_tag latest
fi

if is_truthy "${TAG_GIT_SHA:-false}"; then
  add_tag "sha-${short_revision}"
fi

if [[ -n "${EXTRA_TAGS:-}" ]]; then
  IFS=',' read -r -a extra_tags <<< "$EXTRA_TAGS"
  for tag in "${extra_tags[@]}"; do
    add_tag "$tag"
  done
fi

build_args=(
  --build-arg "OCI_IMAGE_CREATED=${created}"
  --build-arg "OCI_IMAGE_REVISION=${revision}"
  --build-arg "OCI_IMAGE_VERSION=${release_tag}"
  --build-arg "OCI_IMAGE_REF_NAME=${images[0]}:${release_tag}"
  --build-arg "OCI_IMAGE_SOURCE=${source_url}"
  --build-arg "OCI_IMAGE_DOCUMENTATION=${documentation_url}"
)

if is_truthy "${PIN_RELEASE:-true}"; then
  build_args+=(--build-arg "BBX_RELEASE_TAG=${release_tag}")
fi

cmd=(docker buildx build)
if [[ -n "${BUILDER:-}" ]]; then
  cmd+=(--builder "$BUILDER")
fi

cmd+=(
  --platform "$PLATFORMS"
  --file "$DOCKERFILE"
)

if is_truthy "${SBOM:-false}"; then
  cmd+=(--sbom=true)
fi

if is_truthy "${PROVENANCE:-false}"; then
  cmd+=(--provenance=true)
fi

cmd+=(
  --push
  "${tag_args[@]}"
  "${build_args[@]}"
  "$ROOT"
)

echo "[publish] BrowserBox release: ${release_tag}"
echo "[publish] Platforms: ${PLATFORMS}"
echo "[publish] Target images:"
for image in "${images[@]}"; do
  echo "[publish]   ${image}"
done

if is_truthy "${DRY_RUN:-false}"; then
  print_command "${cmd[@]}"
  exit 0
fi

if ! is_truthy "${SKIP_REGISTRY_LOGIN:-false}"; then
  login_target_registries "${images[@]}"
fi

print_command "${cmd[@]}"
exec "${cmd[@]}"
