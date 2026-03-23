#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "browserbox-action v1 supports Linux runners only."
fi

license_key="${BROWSERBOX_ACTION_LICENSE_KEY:-}"
install_url="${BROWSERBOX_ACTION_INSTALL_URL:-https://browserbox.io/install.sh}"
hostname="${BROWSERBOX_ACTION_HOSTNAME:-localhost}"
email="${BROWSERBOX_ACTION_EMAIL:-actions@browserbox.io}"
install_doc_viewer="${BROWSERBOX_ACTION_INSTALL_DOC_VIEWER:-false}"
status_mode="${BROWSERBOX_ACTION_STATUS_MODE:-}"

[[ -n "$license_key" ]] || fail "BROWSERBOX_ACTION_LICENSE_KEY is required."
[[ -n "$install_url" ]] || fail "BROWSERBOX_ACTION_INSTALL_URL is required."

missing=()
apt_packages=()

if ! command -v curl >/dev/null 2>&1; then
  missing+=("curl")
  apt_packages+=("curl")
fi

if ! command -v jq >/dev/null 2>&1; then
  missing+=("jq")
  apt_packages+=("jq")
fi

if ! command -v xxd >/dev/null 2>&1; then
  missing+=("xxd")
  apt_packages+=("vim-common")
fi

if ! command -v sudo >/dev/null 2>&1; then
  missing+=("sudo")
  apt_packages+=("sudo")
fi

if ((${#apt_packages[@]} > 0)); then
  command -v apt-get >/dev/null 2>&1 || fail "Missing required commands (${missing[*]}) and apt-get is unavailable."
  sudo apt-get update -y
  sudo apt-get install -y "${apt_packages[@]}"
fi

export LICENSE_KEY="$license_key"
export BBX_TEST_AGREEMENT="true"
export BBX_HOSTNAME="$hostname"
export EMAIL="$email"
export INSTALL_DOC_VIEWER="$install_doc_viewer"

if [[ -n "$status_mode" ]]; then
  export STATUS_MODE="$status_mode"
fi

echo "::add-mask::$LICENSE_KEY"
curl -fsSL "$install_url" | bash

command -v bbx >/dev/null 2>&1 || fail "bbx was not found in PATH after installation."
