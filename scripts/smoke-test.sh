#!/usr/bin/env bash
set -euo pipefail

# BrowserBox Smoke Test Script
# Usage: ./smoke-test.sh <url>

URL="${1:-}"

if [[ -z "$URL" ]]; then
  echo "Usage: $0 <url>"
  exit 1
fi

echo "Running smoke test against: $URL"

# We use -L to follow redirects and --retry to handle tunnel startup lag.
# Cloudflare tunnels can take a few seconds to become fully ready.
MAX_ATTEMPTS=10
ATTEMPT=1
SUCCESS=false

while (( ATTEMPT <= MAX_ATTEMPTS )); do
  echo "[Attempt $ATTEMPT/$MAX_ATTEMPTS] Checking accessibility..."
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$URL")
  echo "Status Code: $STATUS_CODE"
  
  if [[ "$STATUS_CODE" -eq 200 || "$STATUS_CODE" -eq 302 ]]; then
    echo "SUCCESS: BrowserBox is accessible!"
    SUCCESS=true
    break
  fi
  
  echo "Not ready yet. Waiting 10 seconds..."
  sleep 10
  (( ATTEMPT++ ))
done

if [[ "$SUCCESS" == "true" ]]; then
  exit 0
else
  echo "FAILURE: BrowserBox is not accessible after $MAX_ATTEMPTS attempts."
  exit 1
fi
