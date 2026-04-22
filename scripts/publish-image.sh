#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build and publish the BrowserBox container image.

Defaults:
  GCR image:        gcr.io/github/browserbox/browserbox
  Docker Hub image: browserbox/browserbox
  Platform:         linux/amd64

Auth prerequisites:
  docker login
  gcloud auth configure-docker gcr.io

Common usage:
  scripts/publish-image.sh
  BROWSERBOX_RELEASE_TAG=v16.8.11 scripts/publish-image.sh
  DRY_RUN=1 scripts/publish-image.sh

Environment overrides:
  GCR_IMAGE                  Full GCR image ref. Empty string disables GCR.
  DOCKERHUB_IMAGE            Full Docker Hub image ref. Empty string disables Docker Hub.
  IMAGE_NAME                 Shared image path used by defaults. Default: browserbox/browserbox
  GCR_PROJECT                GCR project used by defaults. Default: github
  BROWSERBOX_RELEASE_TAG     BrowserBox release to install. Default: latest GitHub release.
  PLATFORMS                  Buildx platforms. Default: linux/amd64
  PUSH_LATEST                Also tag latest. Default: true
  TAG_WITHOUT_V              For vX.Y.Z tags, also push X.Y.Z. Default: true
  TAG_GIT_SHA                Also tag sha-<short-sha>. Default: false
  EXTRA_TAGS                 Comma-separated additional tags.
  PIN_RELEASE                Pass BROWSERBOX_RELEASE_TAG to Dockerfile. Default: true
  SBOM                       Add buildx --sbom=true. Default: false
  PROVENANCE                 Add buildx --provenance=true. Default: false
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
IMAGE_NAME="${IMAGE_NAME:-browserbox/browserbox}"
GCR_PROJECT="${GCR_PROJECT:-github}"
GCR_IMAGE="${GCR_IMAGE-gcr.io/${GCR_PROJECT}/${IMAGE_NAME}}"
DOCKERHUB_IMAGE="${DOCKERHUB_IMAGE-${IMAGE_NAME}}"
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
if [[ -n "$GCR_IMAGE" ]]; then
  images+=("$(normalize_ref "$GCR_IMAGE")")
fi
if [[ -n "$DOCKERHUB_IMAGE" ]]; then
  images+=("$(normalize_ref "$DOCKERHUB_IMAGE")")
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

print_command "${cmd[@]}"
exec "${cmd[@]}"
