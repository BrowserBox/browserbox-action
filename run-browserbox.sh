#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./run-browserbox.sh [options]

Launch the BrowserBox GitHub Actions runner workflow and print the live link.

Options:
  --license-key KEY       Set/update the repo secret BBX_LICENSE_KEY before running.
  --repo OWNER/NAME       Repository to run the workflow in.
  --ref REF               Branch/ref to run. Defaults to the current branch or main.
  --timeout MINUTES       Session timeout. Defaults to 10.
  --workflow NAME         Workflow name or file. Defaults to "Live Smoke Run".
  --no-open              Do not open the tracking issue in a browser.
  -h, --help              Show this help.

Environment:
  BBX_LICENSE_KEY, BROWSERBOX_LICENSE_KEY, or BROWSERBOX_ACTION_LICENSE_KEY
                          Used when --license-key is not supplied.
  BROWSERBOX_RUN_REPO     Default repository, in owner/name form.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[browserbox] %s\n' "$*"
}

remote_repo() {
  local remote="$1"
  local url

  url="$(git remote get-url "$remote" 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1

  case "$url" in
    git@github.com:*.git)
      url="${url#git@github.com:}"
      url="${url%.git}"
      ;;
    git@github.com:*)
      url="${url#git@github.com:}"
      ;;
    https://github.com/*.git)
      url="${url#https://github.com/}"
      url="${url%.git}"
      ;;
    https://github.com/*)
      url="${url#https://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$url" == */* ]] || return 1
  printf '%s\n' "$url"
}

workflow_exists() {
  local repo="$1"
  local workflow="$2"
  gh workflow view "$workflow" --repo "$repo" >/dev/null 2>&1
}

resolve_repo() {
  local workflow="$1"
  local repo="${BROWSERBOX_RUN_REPO:-}"
  local candidate
  local candidates=()

  if [[ -n "$repo" ]]; then
    printf '%s\n' "$repo"
    return 0
  fi

  for remote in origin test-origin; do
    candidate="$(remote_repo "$remote" 2>/dev/null || true)"
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done

  candidate="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [[ -n "$candidate" ]] && candidates+=("$candidate")

  for candidate in "${candidates[@]}"; do
    if workflow_exists "$candidate" "$workflow"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  [[ "${#candidates[@]}" -gt 0 ]] || die "could not infer a GitHub repo; pass --repo OWNER/NAME"
  printf '%s\n' "${candidates[0]}"
}

open_url() {
  local url="$1"

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v gio >/dev/null 2>&1; then
    gio open "$url" >/dev/null 2>&1 || true
  fi
}

find_latest_dispatch_run() {
  local repo="$1"
  local workflow="$2"
  local ref="$3"
  local run_line=""

  for _ in $(seq 1 60); do
    run_line="$(
      gh run list \
        --repo "$repo" \
        --workflow "$workflow" \
        --event workflow_dispatch \
        --limit 20 \
        --json databaseId,headBranch,url,status \
        --jq ".[] | select(.headBranch == \"${ref}\") | [.databaseId, .url, .status] | @tsv" \
        2>/dev/null | head -n 1
    )"

    if [[ -z "$run_line" ]]; then
      run_line="$(
        gh run list \
          --repo "$repo" \
          --workflow "$workflow" \
          --event workflow_dispatch \
          --limit 1 \
          --json databaseId,url,status \
          --jq '.[] | [.databaseId, .url, .status] | @tsv' \
          2>/dev/null | head -n 1
      )"
    fi

    [[ -n "$run_line" ]] && printf '%s\n' "$run_line" && return 0
    sleep 2
  done

  return 1
}

wait_for_tracking_issue() {
  local repo="$1"
  local run_id="$2"
  local status
  local issue_line

  for _ in $(seq 1 180); do
    issue_line="$(
      gh issue list \
        --repo "$repo" \
        --state all \
        --search "\"Live BrowserBox run ${run_id}\" in:title" \
        --limit 10 \
        --json number,title,url \
        --jq ".[] | select(.title == \"Live BrowserBox run ${run_id}\") | [.number, .url] | @tsv" \
        2>/dev/null | head -n 1
    )"

    if [[ -n "$issue_line" ]]; then
      printf '%s\n' "$issue_line"
      return 0
    fi

    status="$(gh run view "$run_id" --repo "$repo" --json status,conclusion --jq '.status + ":" + (.conclusion // "")' 2>/dev/null || true)"
    log "waiting for tracking issue; run=${status:-unknown}"
    [[ "$status" == completed:* ]] && return 1
    sleep 5
  done

  return 1
}

wait_for_login_link() {
  local repo="$1"
  local issue_number="$2"
  local run_id="$3"
  local link
  local status

  for _ in $(seq 1 180); do
    link="$(
      gh issue view "$issue_number" \
        --repo "$repo" \
        --comments \
        --json comments \
        --jq '.comments[].body' \
        2>/dev/null |
        grep -aoE 'https://[A-Za-z0-9-]+\.trycloudflare\.com/login\?token=[A-Za-z0-9._~%+-]+' |
        tail -n 1 || true
    )"

    if [[ -n "$link" ]]; then
      printf '%s\n' "$link"
      return 0
    fi

    status="$(gh run view "$run_id" --repo "$repo" --json status,conclusion --jq '.status + ":" + (.conclusion // "")' 2>/dev/null || true)"
    log "waiting for login link on issue #${issue_number}; run=${status:-unknown}"
    [[ "$status" == completed:* ]] && return 1
    sleep 10
  done

  return 1
}

license_key="${BBX_LICENSE_KEY:-${BROWSERBOX_LICENSE_KEY:-${BROWSERBOX_ACTION_LICENSE_KEY:-}}}"
repo_arg=""
ref="$(git branch --show-current 2>/dev/null || true)"
ref="${ref:-main}"
timeout_mins="10"
workflow="Live Smoke Run"
open_issue="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --license-key)
      [[ $# -ge 2 ]] || die "--license-key requires a value"
      license_key="$2"
      shift 2
      ;;
    --license-key=*)
      license_key="${1#*=}"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      repo_arg="$2"
      shift 2
      ;;
    --repo=*)
      repo_arg="${1#*=}"
      shift
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      ref="$2"
      shift 2
      ;;
    --ref=*)
      ref="${1#*=}"
      shift
      ;;
    --timeout)
      [[ $# -ge 2 ]] || die "--timeout requires a value"
      timeout_mins="$2"
      shift 2
      ;;
    --timeout=*)
      timeout_mins="${1#*=}"
      shift
      ;;
    --workflow)
      [[ $# -ge 2 ]] || die "--workflow requires a value"
      workflow="$2"
      shift 2
      ;;
    --workflow=*)
      workflow="${1#*=}"
      shift
      ;;
    --no-open)
      open_issue="false"
      shift
      ;;
    --open)
      open_issue="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v gh >/dev/null 2>&1 || die "gh is required"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
[[ "$timeout_mins" =~ ^[0-9]+$ ]] || die "--timeout must be an integer number of minutes"

if [[ -n "$repo_arg" ]]; then
  repo="$repo_arg"
else
  repo="$(resolve_repo "$workflow")"
fi

log "repo: ${repo}"
log "ref: ${ref}"
log "workflow: ${workflow}"

if [[ -n "$license_key" ]]; then
  log "updating repo secret BBX_LICENSE_KEY"
  printf '%s' "$license_key" | gh secret set BBX_LICENSE_KEY --repo "$repo" >/dev/null
else
  log "no license key supplied; using existing repo secret BBX_LICENSE_KEY"
fi

log "dispatching workflow"
gh workflow run "$workflow" --repo "$repo" --ref "$ref" -f "timeout=${timeout_mins}"

run_line="$(find_latest_dispatch_run "$repo" "$workflow" "$ref")" || die "workflow was dispatched, but no run appeared"
IFS=$'\t' read -r run_id run_url run_status <<< "$run_line"

log "run: ${run_url} (${run_status})"

issue_line="$(wait_for_tracking_issue "$repo" "$run_id")" || die "tracking issue was not created"
IFS=$'\t' read -r issue_number issue_url <<< "$issue_line"

printf 'Tracking issue: %s\n' "$issue_url"
if [[ "$open_issue" == "true" ]]; then
  open_url "$issue_url"
fi

login_link="$(wait_for_login_link "$repo" "$issue_number" "$run_id")" || die "login link was not posted to issue #${issue_number}"

printf 'Login link: %s\n' "$login_link"
