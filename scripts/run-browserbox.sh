#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

wait_for_login_link() {
  local file="$1"
  local attempts="${2:-90}"
  local login_link=""

  for ((i = 0; i < attempts; i++)); do
    if [[ -s "$file" ]]; then
      login_link="$(tr -d '\r' < "$file" | head -n 1)"
      if [[ -n "$login_link" ]]; then
        printf '%s\n' "$login_link"
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

extract_login_link_from_log() {
  local log_file="$1"
  grep -oE 'https://[^[:space:]]+/login\?token=[^[:space:]]+' "$log_file" | tail -n 1 || true
}

license_key="${BROWSERBOX_ACTION_LICENSE_KEY:-}"
tunnel="${BROWSERBOX_ACTION_TUNNEL:-none}"
port="${BROWSERBOX_ACTION_PORT:-8080}"
hostname="${BROWSERBOX_ACTION_HOSTNAME:-localhost}"
email="${BROWSERBOX_ACTION_EMAIL:-actions@browserbox.io}"
install_doc_viewer="${BROWSERBOX_ACTION_INSTALL_DOC_VIEWER:-false}"
status_mode="${BROWSERBOX_ACTION_STATUS_MODE:-}"
create_summary="${BROWSERBOX_ACTION_CREATE_SUMMARY:-true}"

[[ -n "$license_key" ]] || fail "BROWSERBOX_ACTION_LICENSE_KEY is required."
[[ "$tunnel" == "none" || "$tunnel" == "cloudflare" || "$tunnel" == "tor" ]] || fail "Unsupported tunnel '$tunnel'. Expected none, cloudflare, or tor."

config_dir="${HOME}/.config/dosaygo/bbpro"
login_link_file="${config_dir}/login.link"
run_log="${RUNNER_TEMP:-/tmp}/browserbox-action-run.log"

mkdir -p "$config_dir"
rm -f "$login_link_file" "$run_log"

export LICENSE_KEY="$license_key"
export BBX_TEST_AGREEMENT="true"
export BBX_HOSTNAME="$hostname"
export EMAIL="$email"
export INSTALL_DOC_VIEWER="$install_doc_viewer"

if [[ -n "$status_mode" ]]; then
  export STATUS_MODE="$status_mode"
fi

echo "::add-mask::$LICENSE_KEY"

case "$tunnel" in
  none)
    bbx stop || true
    bbx setup -p "$port" --hostname "$hostname"
    bbx start
    login_link="$(wait_for_login_link "$login_link_file" 90)" || fail "Timed out waiting for BrowserBox login link."
    ;;
  cloudflare)
    bbx cf-run --background --port "$port" >"$run_log" 2>&1 || {
      cat "$run_log" >&2
      fail "bbx cf-run failed."
    }
    login_link="$(wait_for_login_link "$login_link_file" 120)" || {
      cat "$run_log" >&2
      fail "Timed out waiting for Cloudflare BrowserBox login link."
    }
    ;;
  tor)
    bbx setup --port "$port" --hostname "$hostname"
    bbx tor-run --no-darkweb >"$run_log" 2>&1 || {
      cat "$run_log" >&2
      fail "bbx tor-run failed."
    }
    login_link="$(extract_login_link_from_log "$run_log")"
    [[ -n "$login_link" ]] || fail "Unable to extract Tor login link from bbx tor-run output."
    printf '%s\n' "$login_link" > "$login_link_file"
    ;;
esac

base_url="$(printf '%s' "$login_link" | sed 's#/login?token=.*##')"

{
  echo "login-link=$login_link"
  echo "base-url=$base_url"
  echo "tunnel=$tunnel"
} >> "$GITHUB_OUTPUT"

if [[ "$create_summary" == "true" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## BrowserBox session"
    echo
    echo "- Tunnel: \`$tunnel\`"
    echo "- Base URL: \`$base_url\`"
    echo "- Login link: \`$login_link\`"
    echo
    echo "Main project: https://github.com/BrowserBox/BrowserBox"
    echo "License keys: https://browserbox.io"
  } >> "$GITHUB_STEP_SUMMARY"
fi
