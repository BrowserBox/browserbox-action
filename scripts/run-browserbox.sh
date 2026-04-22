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

extract_cloudflare_login_link() {
  local source_file="$1"
  [[ -f "$source_file" ]] || return 0
  grep -aoE 'https://[A-Za-z0-9-]+\.trycloudflare\.com/login\?token=[A-Za-z0-9._~%+-]+' "$source_file" | tail -n 1 || true
}

base_url_from_login_link() {
  printf '%s' "$1" | sed 's#/login?token=.*##'
}

ensure_gh_token() {
  if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
    export GH_TOKEN="$GITHUB_TOKEN"
  fi
}

broadcast_issue_comment() {
  local body="$1"

  [[ -n "$broadcast_issue_number" ]] || return 0
  if [[ -z "$broadcast_issue_repo" ]]; then
    echo "::warning::Skipping BrowserBox issue broadcast because no GitHub repository is available."
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "::warning::Skipping BrowserBox issue broadcast because gh is not installed."
    return 0
  fi

  ensure_gh_token
  if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    echo "::warning::Skipping BrowserBox issue broadcast because no GitHub token is available."
    return 0
  fi

  echo "[Broadcast] Posting BrowserBox link to ${broadcast_issue_repo}#${broadcast_issue_number}..."
  if ! gh issue comment "$broadcast_issue_number" --repo "$broadcast_issue_repo" --body "$body"; then
    echo "::warning::Failed to post BrowserBox link to issue #${broadcast_issue_number}."
  fi
}

broadcast_login_link() {
  local title="${1:-BrowserBox login link}"
  local run_url=""

  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
    run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  fi

  local body
  body="$(cat <<EOF
## ${title}

- Tunnel: \`${tunnel}\`
- Service mode: \`${service_mode}\`
- Base URL: \`${base_url}\`
- Timeout: \`${timeout_mins}m\`
EOF
)"

  if [[ -n "$run_url" ]]; then
    body="${body}"$'\n'"- Run: ${run_url}"
  fi

  body="${body}"$'\n\n'"Login link:"$'\n'"${login_link}"
  broadcast_issue_comment "$body"
}

stop_cloudflare_runner() {
  local pid="${1:-}"
  local wait_seconds="${2:-20}"

  [[ -n "$pid" ]] || return 0
  kill -0 "$pid" 2>/dev/null || return 0

  kill -INT "$pid" 2>/dev/null || true
  for ((i = 0; i < wait_seconds; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done

  kill -TERM "$pid" 2>/dev/null || true
  for ((i = 0; i < 5; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done

  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

license_key="${BROWSERBOX_ACTION_LICENSE_KEY:-}"
tunnel="${BROWSERBOX_ACTION_TUNNEL:-cloudflare}"
port="${BROWSERBOX_ACTION_PORT:-8080}"
service_mode="${BROWSERBOX_ACTION_SERVICE_MODE:-minimal}"
hostname="${BROWSERBOX_ACTION_HOSTNAME:-localhost}"
email="${BROWSERBOX_ACTION_EMAIL:-actions@browserbox.io}"
install_doc_viewer="${BROWSERBOX_ACTION_INSTALL_DOC_VIEWER:-false}"
status_mode="${BROWSERBOX_ACTION_STATUS_MODE:-}"
create_summary="${BROWSERBOX_ACTION_CREATE_SUMMARY:-true}"
timeout_mins="${BROWSERBOX_ACTION_TIMEOUT:-30}"
cloudflare_link_timeout_seconds="${BROWSERBOX_ACTION_CLOUDFLARE_LINK_TIMEOUT:-600}"
broadcast_issue_number="${BROWSERBOX_ACTION_BROADCAST_ISSUE_NUMBER:-${BROADCAST_ISSUE_NUMBER:-}}"
broadcast_issue_repo="${BROWSERBOX_ACTION_BROADCAST_ISSUE_REPO:-${BROADCAST_ISSUE_REPO:-${GITHUB_REPOSITORY:-}}}"

# Sanitize timeout: min 1, max 150
if [[ ! "$timeout_mins" =~ ^[0-9]+$ ]]; then
  timeout_mins=30
fi
if (( timeout_mins < 1 )); then timeout_mins=1; fi
if (( timeout_mins > 150 )); then timeout_mins=150; fi

if [[ ! "$cloudflare_link_timeout_seconds" =~ ^[0-9]+$ ]]; then
  cloudflare_link_timeout_seconds=600
fi
if (( cloudflare_link_timeout_seconds < 60 )); then cloudflare_link_timeout_seconds=60; fi
if (( cloudflare_link_timeout_seconds > 900 )); then cloudflare_link_timeout_seconds=900; fi

[[ -n "$license_key" ]] || fail "BROWSERBOX_ACTION_LICENSE_KEY is required."
[[ "$tunnel" == "none" || "$tunnel" == "cloudflare" || "$tunnel" == "tor" ]] || fail "Unsupported tunnel '$tunnel'. Expected none, cloudflare, or tor."
[[ "$service_mode" == "minimal" || "$service_mode" == "full" ]] || fail "Unsupported service mode '$service_mode'. Expected minimal or full."

config_dir="${HOME}/.config/dosaygo/bbpro"
login_link_file="${config_dir}/login.link"
run_log="${RUNNER_TEMP:-/tmp}/browserbox-action-run.log"

mkdir -p "$config_dir"
rm -f "$login_link_file" "$run_log"

export LICENSE_KEY="$license_key"
export BBX_TEST_AGREEMENT="true"
export BBX_NO_UPDATE="true"
export BBX_HOSTNAME="$hostname"
export EMAIL="$email"
export INSTALL_DOC_VIEWER="$install_doc_viewer"

case "$service_mode" in
  minimal)
    export BBX_MINIMAL_MODE="true"
    ;;
  full)
    unset BBX_MINIMAL_MODE || true
    ;;
esac

if [[ -n "$status_mode" ]]; then
  export STATUS_MODE="$status_mode"
fi

echo "::add-mask::$LICENSE_KEY"
echo "::notice::BrowserBox tunnel=$tunnel service_mode=$service_mode BBX_NO_UPDATE=true timeout=${timeout_mins}m"

case "$tunnel" in
  none)
    bbx stop || true
    bbx setup -p "$port" --hostname "$hostname"
    bbx start
    login_link="$(wait_for_login_link "$login_link_file" 90)" || fail "Timed out waiting for BrowserBox login link."
    ;;
  cloudflare)
    # bbx cf-run is a foreground command that writes login.link twice:
    # first with a localhost URL (from setup_bbpro), then with the
    # verified Cloudflare tunnel URL once cloudflared is up. We run it
    # in our own background and wait only for the public trycloudflare link.
    bbx cf-run --port "$port" >"$run_log" 2>&1 &
    cf_pid=$!

    # cf-run can spend time in setup/certification, local readiness retries,
    # and up to three Cloudflare URL/verification attempts.
    login_link=""
    for ((i = 0; i < cloudflare_link_timeout_seconds; i++)); do
      candidate="$(extract_cloudflare_login_link "$login_link_file")"
      if [[ -z "$candidate" ]]; then
        candidate="$(extract_cloudflare_login_link "$run_log")"
      fi
      if [[ -n "$candidate" ]]; then
        login_link="$candidate"
        break
      fi
      if ! kill -0 "$cf_pid" 2>/dev/null; then
        cat "$run_log" >&2
        fail "bbx cf-run exited before producing a tunnel URL."
      fi
      sleep 1
    done

    if [[ -z "$login_link" ]]; then
      stop_cloudflare_runner "$cf_pid" 20
      tail -n 80 "$run_log" >&2
      fail "Timed out after ${cloudflare_link_timeout_seconds}s waiting for public Cloudflare tunnel URL."
    fi
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

base_url="$(base_url_from_login_link "$login_link")"

{
  echo "login-link=$login_link"
  echo "base-url=$base_url"
  echo "tunnel=$tunnel"
  echo "service-mode=$service_mode"
} >> "$GITHUB_OUTPUT"

if [[ "$create_summary" == "true" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## BrowserBox session"
    echo
    echo "- Tunnel: \`$tunnel\`"
    echo "- Service mode: \`$service_mode\`"
    echo "- No update checks: \`true\`"
    echo "- Base URL: \`$base_url\`"
    echo "- Login link: \`$login_link\`"
    echo
    echo "Main project: https://github.com/BrowserBox/BrowserBox"
    echo "License keys: https://browserbox.io"
  } >> "$GITHUB_STEP_SUMMARY"
fi

# Surface the link in the GitHub Actions UI banner while the job is still running.
echo "::notice title=BrowserBox Login Link::$login_link"
broadcast_login_link "BrowserBox login link"

echo "--------------------------------------------------------------------------------"
echo "BrowserBox is running!"
echo "Login link: $login_link"
echo "This session will stay active for ${timeout_mins} minutes or until you cancel it."
echo "--------------------------------------------------------------------------------"

# Background smoke test for public accessibility
(
  echo "[Smoke Test] Waiting for tunnel to propagate (up to 2 minutes)..."
  MAX_SMOKE_ATTEMPTS=12
  SMOKE_ATTEMPT=1
  SMOKE_SUCCESS=false
  
  while (( SMOKE_ATTEMPT <= MAX_SMOKE_ATTEMPTS )); do
    sleep 10
    echo "[Smoke Test Attempt $SMOKE_ATTEMPT/$MAX_SMOKE_ATTEMPTS] Checking $base_url ..."
    # Try with verbose output to diagnose 403 or other issues
    RESPONSE=$(curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" --max-time 10 -w "%{http_code}" "$base_url" -o /tmp/smoke_out.html || echo "CURL_FAILED")
    
    echo "[Smoke Test] Response code: $RESPONSE"
    
    if [[ "$RESPONSE" =~ ^(200|302|401)$ ]]; then
      echo "[Smoke Test] SUCCESS: BrowserBox is accessible via tunnel."
      SMOKE_SUCCESS=true
      break
    elif [[ "$RESPONSE" == "403" ]]; then
      echo "[Smoke Test] Received 403. This might be Cloudflare WAF or Bot Protection. Checking content..."
      if grep -qi "BrowserBox" /tmp/smoke_out.html; then
        echo "[Smoke Test] SUCCESS: Found 'BrowserBox' in 403 response body. It is reachable!"
        SMOKE_SUCCESS=true
        break
      fi
    fi
    (( SMOKE_ATTEMPT++ ))
  done
  
  if [[ "$SMOKE_SUCCESS" != "true" ]]; then
    echo "[Smoke Test] WARNING: BrowserBox might not be publicly accessible yet (or check failed)."
  fi
) &

# Keep alive loop
end_time=$(( $(date +%s) + timeout_mins * 60 ))
while (( $(date +%s) < end_time )); do
  if [[ -n "${cf_pid:-}" ]] && ! kill -0 "$cf_pid" 2>/dev/null; then
    echo "::error::bbx cf-run died; tunnel is no longer active."
    tail -n 80 "$run_log" >&2 || true
    exit 1
  fi
  if [[ "$tunnel" == "cloudflare" ]]; then
    refreshed_link="$(extract_cloudflare_login_link "$login_link_file")"
    if [[ -n "$refreshed_link" && "$refreshed_link" != "$login_link" ]]; then
      login_link="$refreshed_link"
      base_url="$(base_url_from_login_link "$login_link")"
      echo "::notice title=BrowserBox Login Link Updated::$login_link"
      broadcast_login_link "BrowserBox login link updated"
    fi
  fi
  echo "[$(date +%T)] BrowserBox is active. Login at: $login_link"
  sleep 60
done

echo "Timeout reached. Stopping BrowserBox."
if [[ -n "${cf_pid:-}" ]]; then
  stop_cloudflare_runner "$cf_pid" 20
fi
bbx stop || true
