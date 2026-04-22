#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./run-browserbox.sh [options]

Launch the BrowserBox GitHub Actions runner workflow and print the live link.

Session options (forwarded to the action):
  --tunnel MODE           Exposure mode: cloudflare | tor | none. Default: cloudflare.
  --service-mode MODE     Service cluster: minimal | full. Default: minimal.
  --port N                Main BrowserBox service port. Default: 8080.
  --hostname NAME         Hostname for local setup (tunnel=none). Default: localhost.
  --email ADDR            Email used for BrowserBox setup. Default: actions@browserbox.io.
  --install-doc-viewer    Install document viewer deps (slower install).
  --no-install-doc-viewer Skip document viewer deps (default).
  --status-mode MODE      Optional STATUS_MODE override passed to BrowserBox.
  --timeout MINUTES       Session timeout in minutes. Default: 10.
  --retries N             Retry failed runs up to N times. Default: 2 (3 total attempts).

Dispatch / repo options:
  --license-key KEY       Set/update the repo secret BBX_LICENSE_KEY before running.
  --repo OWNER/NAME       Explicit repo to run in. Default: <you>/browserbox-runner
                          (a dedicated runner repo; created on first run).
  --repo-name NAME        Override the default runner repo name (default: browserbox-runner).
  --ref REF               Branch/ref to run. Defaults to the current branch or main.
  --workflow NAME         Workflow name or file. Default: "Live Smoke Run".
  --public                Create the bootstrap repo as public.
  --private               Create the bootstrap repo as private (default).
  --no-create-repo        Fail instead of creating/bootstrapping a repo.
  --remote NAME           Git remote name for bootstrap pushes. Default: browserbox-runner.
  --no-open               Do not open the tracking issue in a browser.
  -h, --help              Show this help.

Examples:
  # Default: cloudflare tunnel, minimal services, 10 minute session
  ./run-browserbox.sh

  # Tor tunnel, 30 minute session
  ./run-browserbox.sh --tunnel tor --timeout 30

  # Local-only (no public tunnel), full services, custom port
  ./run-browserbox.sh --tunnel none --service-mode full --port 9000

Environment:
  BBX_LICENSE_KEY, BROWSERBOX_LICENSE_KEY, or BROWSERBOX_ACTION_LICENSE_KEY
                          Used when --license-key is not supplied.
  BROWSERBOX_RUN_REPO     Default repository, in owner/name form. Overrides
                          the default runner repo.
  BROWSERBOX_RUN_REPO_NAME
                          Override the default runner repo name.

Notes:
- By default the script targets a dedicated <you>/browserbox-runner repo,
  NOT the current directory's git remote. This keeps runs isolated from the
  project you're working in.
- First run creates the runner repo. Pass --license-key KEY then, or set the
  BBX_LICENSE_KEY secret on the runner repo yourself. Subsequent runs reuse
  the stored secret.
- Session options (--tunnel, --service-mode, --port, --hostname, --email,
  --install-doc-viewer, --status-mode) require the workflow on the runner
  repo to expose matching workflow_dispatch inputs. The bundled
  .github/workflows/smoke-run.yml does.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[browserbox] %s\n' "$*" >&2
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

repo_exists() {
  local repo="$1"
  gh repo view "$repo" >/dev/null 2>&1
}

authenticated_owner() {
  gh api user --jq .login
}

repo_clone_url() {
  local repo="$1"
  local protocol

  protocol="$(gh config get git_protocol -h github.com 2>/dev/null || true)"
  if [[ "$protocol" == "ssh" ]]; then
    gh repo view "$repo" --json sshUrl --jq .sshUrl
  else
    gh repo view "$repo" --json url --jq .url
  fi
}

sanitize_repo_name() {
  local raw="$1"
  local clean

  clean="$(printf '%s' "$raw" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')"
  clean="${clean#.}"
  clean="${clean%-}"
  printf '%s\n' "${clean:-browserbox-runner}"
}

default_auto_repo() {
  local owner="$1"
  local name="${BROWSERBOX_RUN_REPO_NAME:-${repo_name_arg:-browserbox-runner}}"
  printf '%s/%s\n' "$owner" "$(sanitize_repo_name "$name")"
}

ensure_git_worktree() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "runner repo does not exist yet and bootstrapping it needs a browserbox-action checkout; either cd into the browserbox-action repo or pass --repo OWNER/NAME pointing at an existing repo that has the workflow"
}

warn_uncommitted_bootstrap_changes() {
  local dirty

  dirty="$(git status --porcelain -- .github/workflows/smoke-run.yml action.yml scripts/run-browserbox.sh run-browserbox.sh 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    log "warning: workflow/action helper files have uncommitted changes; only committed HEAD will be pushed"
  fi
}

ensure_remote() {
  local remote="$1"
  local repo="$2"
  local url

  url="$(repo_clone_url "$repo")"
  if git remote get-url "$remote" >/dev/null 2>&1; then
    if [[ "$(git remote get-url "$remote")" != "$url" ]]; then
      git remote set-url "$remote" "$url"
    fi
  else
    git remote add "$remote" "$url"
  fi
}

wait_for_workflow() {
  local repo="$1"
  local workflow="$2"

  for _ in $(seq 1 60); do
    workflow_exists "$repo" "$workflow" && return 0
    sleep 2
  done

  return 1
}

bootstrap_repo() {
  local repo="$1"
  local workflow="$2"
  local ref="$3"

  [[ "$create_repo" == "true" ]] || die "no repo with workflow \"${workflow}\" found; pass --repo OWNER/NAME or remove --no-create-repo"
  ensure_git_worktree
  warn_uncommitted_bootstrap_changes

  if repo_exists "$repo"; then
    log "bootstrap repo exists: ${repo}"
  else
    log "creating ${repo_visibility} repo: ${repo}"
    gh repo create "$repo" "--${repo_visibility}" --disable-wiki \
      --description "Private BrowserBox GitHub Actions runner" >&2
  fi

  ensure_remote "$bootstrap_remote" "$repo"

  log "pushing current HEAD to ${repo}:${ref}"
  if ! git push "$bootstrap_remote" "HEAD:refs/heads/${ref}"; then
    die "failed to push current HEAD to ${repo}:${ref}; resolve the git push error or pass a different --repo"
  fi

  log "waiting for workflow \"${workflow}\" to become available"
  wait_for_workflow "$repo" "$workflow" || die "workflow \"${workflow}\" was not found in ${repo} after pushing ${ref}"
}

resolve_repo() {
  local workflow="$1"
  local ref="$2"
  local explicit_repo="${repo_arg:-${BROWSERBOX_RUN_REPO:-}}"
  local candidate

  if [[ -n "$explicit_repo" ]]; then
    if workflow_exists "$explicit_repo" "$workflow"; then
      printf '%s\n' "$explicit_repo"
      return 0
    fi
    bootstrap_repo "$explicit_repo" "$workflow" "$ref"
    printf '%s\n' "$explicit_repo"
    return 0
  fi

  candidate="$(default_auto_repo "$(authenticated_owner)")"
  if workflow_exists "$candidate" "$workflow"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  log "dedicated runner repo not found; bootstrapping ${candidate}"
  bootstrap_repo "$candidate" "$workflow" "$ref"
  printf '%s\n' "$candidate"
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

check_link_accessible() {
  local link="$1"
  local base_url="${link%/login?token=*}"
  local response
  local out_file
  out_file="$(mktemp)"

  if ! command -v curl >/dev/null 2>&1; then
    rm -f "$out_file"
    return 0
  fi

  response=$(curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" --max-time 10 -w "%{http_code}" "$base_url" -o "$out_file" || echo "CURL_FAILED")

  if [[ "$response" =~ ^(200|403)$ ]]; then
    if grep -qi "BrowserBox" "$out_file" 2>/dev/null; then
      rm -f "$out_file"
      return 0
    fi
  elif [[ "$response" =~ ^(302|401)$ ]]; then
    rm -f "$out_file"
    return 0
  fi

  rm -f "$out_file"
  return 1
}

compute_dispatch_iso() {
  local buffer_seconds="${1:-5}"
  local out
  out="$(date -u -v-"${buffer_seconds}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  out="$(date -u -d "-${buffer_seconds} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

find_dispatched_run() {
  local repo="$1"
  local workflow="$2"
  local ref="$3"
  local dispatch_iso="$4"
  local run_line=""

  for _ in $(seq 1 90); do
    run_line="$(
      gh run list \
        --repo "$repo" \
        --workflow "$workflow" \
        --event workflow_dispatch \
        --branch "$ref" \
        --limit 20 \
        --json databaseId,url,status,createdAt \
        --jq "[.[] | select(.createdAt >= \"${dispatch_iso}\")] | sort_by(.createdAt) | reverse | .[0] // empty | [.databaseId, .url, .status] | @tsv" \
        2>/dev/null | head -n 1
    )"

    [[ -n "$run_line" ]] && printf '%s\n' "$run_line" && return 0
    sleep 2
  done

  return 1
}

show_run_failure() {
  local repo="$1"
  local run_id="$2"

  log "last 80 lines of failed run logs for ${run_id}:"
  gh run view "$run_id" --repo "$repo" --log-failed 2>/dev/null | tail -n 80 >&2 || true
}

verify_license_available() {
  local repo="$1"
  local provided_key="$2"
  [[ -z "$provided_key" ]] || return 0

  local secrets
  secrets="$(gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || true)"
  # If listing failed (e.g., insufficient permissions), skip pre-flight rather than false-fail.
  [[ -n "$secrets" ]] || return 0

  if ! printf '%s\n' "$secrets" | grep -qx "BBX_LICENSE_KEY"; then
    die "repo ${repo} has no BBX_LICENSE_KEY secret; pass --license-key KEY, set BBX_LICENSE_KEY env, or add the secret"
  fi
}

close_tracking_issue() {
  local repo="$1"
  local issue_number="$2"
  local reason="$3"

  [[ -n "$issue_number" ]] || return 0
  gh issue close "$issue_number" --repo "$repo" --reason "not planned" \
    --comment "Auto-closed by run-browserbox.sh: ${reason}" >/dev/null 2>&1 || true
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
      if check_link_accessible "$link"; then
        printf '%s\n' "$link"
        return 0
      fi
      log "found link on issue #${issue_number}, but it is not yet accessible; still waiting..."
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
repo_name_arg=""
ref="$(git branch --show-current 2>/dev/null || true)"
ref="${ref:-main}"
timeout_mins="10"
workflow="Live Smoke Run"
open_issue="true"
create_repo="true"
repo_visibility="private"
bootstrap_remote="browserbox-runner"
tunnel=""
service_mode=""
port=""
hostname_opt=""
email_opt=""
install_doc_viewer=""
status_mode_opt=""
retries="2"

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
    --repo-name)
      [[ $# -ge 2 ]] || die "--repo-name requires a value"
      repo_name_arg="$2"
      shift 2
      ;;
    --repo-name=*)
      repo_name_arg="${1#*=}"
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
    --tunnel)
      [[ $# -ge 2 ]] || die "--tunnel requires a value"
      tunnel="$2"
      shift 2
      ;;
    --tunnel=*)
      tunnel="${1#*=}"
      shift
      ;;
    --service-mode)
      [[ $# -ge 2 ]] || die "--service-mode requires a value"
      service_mode="$2"
      shift 2
      ;;
    --service-mode=*)
      service_mode="${1#*=}"
      shift
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port requires a value"
      port="$2"
      shift 2
      ;;
    --port=*)
      port="${1#*=}"
      shift
      ;;
    --hostname)
      [[ $# -ge 2 ]] || die "--hostname requires a value"
      hostname_opt="$2"
      shift 2
      ;;
    --hostname=*)
      hostname_opt="${1#*=}"
      shift
      ;;
    --email)
      [[ $# -ge 2 ]] || die "--email requires a value"
      email_opt="$2"
      shift 2
      ;;
    --email=*)
      email_opt="${1#*=}"
      shift
      ;;
    --install-doc-viewer)
      install_doc_viewer="true"
      shift
      ;;
    --install-doc-viewer=*)
      install_doc_viewer="${1#*=}"
      shift
      ;;
    --no-install-doc-viewer)
      install_doc_viewer="false"
      shift
      ;;
    --status-mode)
      [[ $# -ge 2 ]] || die "--status-mode requires a value"
      status_mode_opt="$2"
      shift 2
      ;;
    --status-mode=*)
      status_mode_opt="${1#*=}"
      shift
      ;;
    --retries)
      [[ $# -ge 2 ]] || die "--retries requires a value"
      retries="$2"
      shift 2
      ;;
    --retries=*)
      retries="${1#*=}"
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
    --public)
      repo_visibility="public"
      shift
      ;;
    --private)
      repo_visibility="private"
      shift
      ;;
    --no-create-repo)
      create_repo="false"
      shift
      ;;
    --remote)
      [[ $# -ge 2 ]] || die "--remote requires a value"
      bootstrap_remote="$2"
      shift 2
      ;;
    --remote=*)
      bootstrap_remote="${1#*=}"
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

command -v gh >/dev/null 2>&1 || die "gh is required. Install GitHub CLI: https://cli.github.com/"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login --scopes repo"
[[ "$timeout_mins" =~ ^[0-9]+$ ]] || die "--timeout must be an integer number of minutes"
[[ "$repo_visibility" == "private" || "$repo_visibility" == "public" ]] || die "repo visibility must be private or public"
[[ -n "$bootstrap_remote" ]] || die "--remote cannot be empty"

if [[ -n "$tunnel" && "$tunnel" != "cloudflare" && "$tunnel" != "tor" && "$tunnel" != "none" ]]; then
  die "--tunnel must be cloudflare, tor, or none"
fi
if [[ -n "$service_mode" && "$service_mode" != "minimal" && "$service_mode" != "full" ]]; then
  die "--service-mode must be minimal or full"
fi
if [[ -n "$port" && ! "$port" =~ ^[0-9]+$ ]]; then
  die "--port must be an integer"
fi
if [[ -n "$install_doc_viewer" && "$install_doc_viewer" != "true" && "$install_doc_viewer" != "false" ]]; then
  die "--install-doc-viewer must be true or false"
fi
[[ "$retries" =~ ^[0-9]+$ ]] || die "--retries must be a non-negative integer"

repo="$(resolve_repo "$workflow" "$ref")"

log "repo: ${repo}"
log "ref: ${ref}"
log "workflow: ${workflow}"

if [[ -n "$license_key" ]]; then
  log "updating repo secret BBX_LICENSE_KEY"
  printf '%s' "$license_key" | gh secret set BBX_LICENSE_KEY --repo "$repo" >/dev/null
else
  log "no license key supplied; using existing repo secret BBX_LICENSE_KEY"
  verify_license_available "$repo" "$license_key"
fi

dispatch_args=(-f "timeout=${timeout_mins}")
[[ -n "$tunnel" ]]             && dispatch_args+=(-f "tunnel=${tunnel}")
[[ -n "$service_mode" ]]       && dispatch_args+=(-f "service-mode=${service_mode}")
[[ -n "$port" ]]               && dispatch_args+=(-f "port=${port}")
[[ -n "$hostname_opt" ]]       && dispatch_args+=(-f "hostname=${hostname_opt}")
[[ -n "$email_opt" ]]          && dispatch_args+=(-f "email=${email_opt}")
[[ -n "$install_doc_viewer" ]] && dispatch_args+=(-f "install-doc-viewer=${install_doc_viewer}")
[[ -n "$status_mode_opt" ]]    && dispatch_args+=(-f "status-mode=${status_mode_opt}")

max_attempts=$((retries + 1))
login_link=""
issue_number=""
issue_url=""
run_url=""
last_error="no attempts succeeded"

for attempt in $(seq 1 "$max_attempts"); do
  if (( attempt > 1 )); then
    log "retrying (attempt ${attempt}/${max_attempts})"
  fi

  dispatch_iso="$(compute_dispatch_iso 5)"
  log "dispatching workflow (attempt ${attempt}/${max_attempts}, dispatch_iso=${dispatch_iso})"
  gh workflow run "$workflow" --repo "$repo" --ref "$ref" "${dispatch_args[@]}" >/dev/null

  if ! run_line="$(find_dispatched_run "$repo" "$workflow" "$ref" "$dispatch_iso")"; then
    last_error="workflow was dispatched, but no matching run appeared (since=${dispatch_iso})"
    log "${last_error}"
    continue
  fi
  IFS=$'\t' read -r run_id run_url run_status <<< "$run_line"
  log "run: ${run_url} (${run_status})"

  if ! issue_line="$(wait_for_tracking_issue "$repo" "$run_id")"; then
    show_run_failure "$repo" "$run_id"
    last_error="tracking issue was not created for run ${run_id}; see ${run_url}"
    log "${last_error}"
    continue
  fi
  IFS=$'\t' read -r issue_number issue_url <<< "$issue_line"
  printf 'Tracking issue: %s\n' "$issue_url"

  if ! login_link="$(wait_for_login_link "$repo" "$issue_number" "$run_id")"; then
    show_run_failure "$repo" "$run_id"
    last_error="login link was not posted to issue #${issue_number}; see ${run_url}"
    log "${last_error}"
    if (( attempt < max_attempts )); then
      close_tracking_issue "$repo" "$issue_number" "${last_error} (attempt ${attempt}/${max_attempts} failed)"
    fi
    login_link=""
    continue
  fi

  break
done

[[ -n "$login_link" ]] || die "$last_error"

if [[ "$open_issue" == "true" && -n "$issue_url" ]]; then
  open_url "$issue_url"
fi

printf 'Login link: %s\n' "$login_link"
