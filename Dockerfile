# syntax=docker/dockerfile:1.7

# General BrowserBox binary image.
#
# Build:
#   docker build --platform linux/amd64 -t browserbox:latest .
#
# Run:
#   docker run --rm -it -p 8080:8080 -e LICENSE_KEY=... browserbox:latest
#
# By default this installs the latest BrowserBox release at build time. Set
# BBX_RELEASE_TAG to pin a release, for example:
#   docker build --build-arg BBX_RELEASE_TAG=v16.8.11 -t browserbox:v16.8.11 .
#
# Publishing metadata can be stamped by CI, for example:
#   docker build \
#     --build-arg OCI_IMAGE_CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
#     --build-arg OCI_IMAGE_REVISION="$(git rev-parse HEAD)" \
#     --build-arg OCI_IMAGE_VERSION="v16.8.11" \
#     -t gcr.io/github/browserbox/browserbox:v16.8.11 .

ARG BBX_IMAGE_PLATFORM=linux/amd64

FROM --platform=${BBX_IMAGE_PLATFORM} debian:bookworm-slim

ARG BBX_INSTALL_URL="https://browserbox.io/install.sh"
ARG BBX_RELEASE_TAG=""
ARG BBX_INSTALL_EMAIL="docker@browserbox.io"
ARG BBX_BUILD_LICENSE_KEY="build-time-placeholder"
ARG BBX_PORT=8080
ARG BBX_HOSTNAME=localhost
ARG BBX_MINIMAL_MODE=true

ARG OCI_IMAGE_TITLE="BrowserBox"
ARG OCI_IMAGE_DESCRIPTION="General BrowserBox binary image with warmed Chromium profile and runtime token refresh"
ARG OCI_IMAGE_SOURCE="https://github.com/BrowserBox/browserbox-action"
ARG OCI_IMAGE_DOCUMENTATION="https://github.com/BrowserBox/browserbox-action#readme"
ARG OCI_IMAGE_URL="https://browserbox.io"
ARG OCI_IMAGE_VENDOR="DOSAYGO Corporation"
ARG OCI_IMAGE_AUTHORS="DOSAYGO Corporation <legal@dosaygo.com>"
ARG OCI_IMAGE_LICENSES="LicenseRef-BrowserBox"
ARG OCI_IMAGE_VERSION="latest"
ARG OCI_IMAGE_REVISION=""
ARG OCI_IMAGE_CREATED=""
ARG OCI_IMAGE_REF_NAME="browserbox"
ARG OCI_IMAGE_BASE_NAME="docker.io/library/debian:bookworm-slim"

LABEL org.opencontainers.image.title="${OCI_IMAGE_TITLE}" \
  org.opencontainers.image.description="${OCI_IMAGE_DESCRIPTION}" \
  org.opencontainers.image.url="${OCI_IMAGE_URL}" \
  org.opencontainers.image.source="${OCI_IMAGE_SOURCE}" \
  org.opencontainers.image.documentation="${OCI_IMAGE_DOCUMENTATION}" \
  org.opencontainers.image.vendor="${OCI_IMAGE_VENDOR}" \
  org.opencontainers.image.authors="${OCI_IMAGE_AUTHORS}" \
  org.opencontainers.image.licenses="${OCI_IMAGE_LICENSES}" \
  org.opencontainers.image.version="${OCI_IMAGE_VERSION}" \
  org.opencontainers.image.revision="${OCI_IMAGE_REVISION}" \
  org.opencontainers.image.created="${OCI_IMAGE_CREATED}" \
  org.opencontainers.image.ref.name="${OCI_IMAGE_REF_NAME}" \
  org.opencontainers.image.base.name="${OCI_IMAGE_BASE_NAME}" \
  io.browserbox.image.kind="general-binary" \
  io.browserbox.install.url="${BBX_INSTALL_URL}" \
  io.browserbox.release.tag="${BBX_RELEASE_TAG}" \
  io.browserbox.default.port="${BBX_PORT}" \
  io.browserbox.default.hostname="${BBX_HOSTNAME}" \
  io.browserbox.minimal_mode="${BBX_MINIMAL_MODE}" \
  io.browserbox.chrome.path="/usr/bin/chromium" \
  io.browserbox.profile.warmed="true" \
  io.browserbox.runtime_setup="fresh-token-on-start"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
  TZ=UTC \
  HOME=/home/bbuser \
  PORT=${BBX_PORT} \
  BBX_HOSTNAME=${BBX_HOSTNAME} \
  BBX_MINIMAL_MODE=${BBX_MINIMAL_MODE} \
  BBX_TEST_AGREEMENT=true \
  BBX_SUDOLESS=false \
  BBX_FORCE_CHROME_INSTALL=false \
  BBX_MANUAL_CLEAN_SLATE=false \
  BBX_ENABLE_FAVICON=true \
  BBX_DEFAULT_HOME_PAGE=https://duckduckgo.com \
  BBX_UI_THEME_OVERRIDE=light \
  GO_SECURE=false \
  CHROME_PATH=/usr/bin/chromium \
  PATH="/home/bbuser/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /root

RUN apt-get update && apt-get install -y --no-install-recommends \
    at \
    build-essential \
    ca-certificates \
    chromium \
    chromium-sandbox \
    curl \
    dnsutils \
    fontconfig \
    ffmpeg \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    fonts-freefont-ttf \
    fonts-ipafont-gothic \
    fonts-kacst \
    fonts-thai-tlwg \
    fonts-wqy-zenhei \
    gconf-service \
    git \
    gnupg \
    htop \
    iproute2 \
    jq \
    libasound2 \
    libappindicator1 \
    libappindicator3-1 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgconf-2-4 \
    libgdk-pixbuf-2.0-0 \
    libnss3 \
    libpango-1.0-0 \
    libvulkan1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxss1 \
    lame \
    login \
    lsb-release \
    ncat \
    net-tools \
    netcat-openbsd \
    nethogs \
    nodejs \
    openssl \
    procps \
    psmisc \
    pulseaudio \
    pulseaudio-utils \
    rsync \
    sudo \
    tini \
    unzip \
    wget \
    xdg-utils \
    xfonts-utils \
    xxd \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN fc-cache -f -v >/dev/null 2>&1 || true

RUN useradd -ms /bin/bash bbuser \
  && echo "bbuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
  && chown root:root /usr/bin/sudo \
  && chmod 4755 /usr/bin/sudo \
  && touch /.dockerenv

USER bbuser
WORKDIR /home/bbuser

# Pulling the release metadata as its own layer helps the default "latest"
# install refresh when the upstream latest release changes.
ADD --chown=bbuser:bbuser https://api.github.com/repos/BrowserBox/BrowserBox/releases/latest /tmp/browserbox-latest-release.json

RUN set -euo pipefail; \
  latest_tag="$(jq -r '.tag_name // empty' /tmp/browserbox-latest-release.json 2>/dev/null || true)"; \
  if [[ -n "${BBX_RELEASE_TAG}" ]]; then \
    export BBX_RELEASE_TAG BBX_NO_UPDATE=true; \
    echo "Installing pinned BrowserBox release ${BBX_RELEASE_TAG}"; \
  else \
    unset BBX_RELEASE_TAG BBX_NO_UPDATE; \
    echo "Installing latest BrowserBox release ${latest_tag:-from official installer}"; \
  fi; \
  export BBX_TEST_AGREEMENT=true; \
  export BBX_FULL_INSTALL=true; \
  export BBX_INSTALL_HOSTNAME="${BBX_HOSTNAME}"; \
  export BBX_HOSTNAME="${BBX_HOSTNAME}"; \
  export BBX_INSTALL_EMAIL="${BBX_INSTALL_EMAIL}"; \
  export EMAIL="${BBX_INSTALL_EMAIL}"; \
  export BBX_FORCE_CHROME_INSTALL=false; \
  unset BBX_SUDOLESS; \
  export INSTALL_DOC_VIEWER=false; \
  curl -fsSL "${BBX_INSTALL_URL}" -o /tmp/install-browserbox.sh; \
  bash /tmp/install-browserbox.sh; \
  rm -f /tmp/install-browserbox.sh; \
  command -v bbx >/dev/null; \
  command -v bbpro >/dev/null; \
  command -v conrun >/dev/null; \
  bbx --version 2>/dev/null || true

ENV BBX_NO_UPDATE=true

# Build-time setup and raw Chromium warmup. The placeholder key only satisfies
# setup's non-empty key requirement; runtime must provide a real LICENSE_KEY.
RUN set -euo pipefail; \
  config_dir="${HOME}/.config/dosaygo/bbpro"; \
  mkdir -p "${config_dir}/browser-cache" "${config_dir}/browser-crashes"; \
  export LICENSE_KEY="${BBX_BUILD_LICENSE_KEY:-build-time-placeholder}"; \
  export BBX_NONINTERACTIVE=true; \
  export BBX_TEST_AGREEMENT=true; \
  export BBX_NO_UPDATE=true; \
  export BBX_SUDOLESS=false; \
  export BBX_HOSTNAME="${BBX_HOSTNAME}"; \
  export EMAIL="${BBX_INSTALL_EMAIL}"; \
  echo "Running build-time bbx setup on ${BBX_HOSTNAME}:${PORT}"; \
  bbx setup --port "${PORT}" --hostname "${BBX_HOSTNAME}" --backend http; \
  chrome_log=/tmp/chromium-warmup.log; \
  chrome_flags=( \
    --no-first-run \
    --no-default-browser-check \
    --test-type \
    --disable-infobars \
    --noerrdialogs \
    --disable-3d-apis \
    --headless=new \
    --restore-last-session \
    --restart \
    --hide-crash-restore-bubble \
    --homepage=about:blank \
    --enable-low-end-device-mode \
    --disable-dev-shm-usage \
    --no-sandbox \
    --disable-features=PrivacySandboxSettings4 \
    --disable-site-isolation-trials \
    --skip-force-online-signin-for-testing \
  ); \
  echo "Soft-launching Chromium to warm ${config_dir}/browser-cache"; \
  /usr/bin/chromium \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=9222 \
    --user-data-dir="${config_dir}/browser-cache" \
    --window-size=1920,1080 \
    --crash-dumps-dir="${config_dir}/browser-crashes" \
    --profile-directory=Default \
    "${chrome_flags[@]}" \
    about:blank >"${chrome_log}" 2>&1 & \
  chrome_pid=$!; \
  chrome_ready=0; \
  for i in $(seq 1 90); do \
    if ! kill -0 "${chrome_pid}" 2>/dev/null; then \
      echo "Chromium exited during warmup" >&2; \
      tail -80 "${chrome_log}" >&2 || true; \
      exit 1; \
    fi; \
    if curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1; then \
      echo "Chromium DevTools endpoint ready; warming for 8s"; \
      sleep 8; \
      chrome_ready=1; \
      break; \
    fi; \
    sleep 1; \
  done; \
  if [[ "${chrome_ready}" != "1" ]]; then \
    echo "Chromium DevTools endpoint did not become ready" >&2; \
    tail -80 "${chrome_log}" >&2 || true; \
    kill -TERM "${chrome_pid}" 2>/dev/null || true; \
    wait "${chrome_pid}" 2>/dev/null || true; \
    exit 1; \
  fi; \
  kill -TERM "${chrome_pid}" 2>/dev/null || true; \
  for _ in $(seq 1 10); do \
    if ! kill -0 "${chrome_pid}" 2>/dev/null; then break; fi; \
    sleep 1; \
  done; \
  kill -KILL "${chrome_pid}" 2>/dev/null || true; \
  wait "${chrome_pid}" 2>/dev/null || true; \
  rm -rf "${config_dir}/browser-crashes"; \
  mkdir -p "${config_dir}/browser-crashes"; \
  rm -f "${config_dir}/login.link" \
        "${config_dir}/test.env" \
        "${config_dir}/tickets/ticket.json" \
        "${config_dir}/tickets/reservation.json"; \
  find "${config_dir}/browser-cache" -maxdepth 2 -type d | sort | head -20

USER root

RUN <<'EOF'
set -euo pipefail
cat > /usr/local/bin/browserbox-entrypoint.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/bbuser}"
export PATH="${HOME}/.local/bin:${PATH}"
export PORT="${PORT:-8080}"
export BBX_HOSTNAME="${BBX_HOSTNAME:-localhost}"
export BBX_BACKEND="${BBX_BACKEND:-http}"
export BBX_TEST_AGREEMENT="${BBX_TEST_AGREEMENT:-true}"
export BBX_NO_UPDATE="${BBX_NO_UPDATE:-true}"
export BBX_SUDOLESS="${BBX_SUDOLESS:-false}"
export BBX_FORCE_CHROME_INSTALL="${BBX_FORCE_CHROME_INSTALL:-false}"
export BBX_MINIMAL_MODE="${BBX_MINIMAL_MODE:-true}"
export CHROME_PATH="${CHROME_PATH:-/usr/bin/chromium}"
export GO_SECURE="${GO_SECURE:-false}"

CONFIG_DIR="${HOME}/.config/dosaygo/bbpro"

is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

shutdown() {
  echo "[browserbox] stopping"
  bbx stop >/dev/null 2>&1 || true
  exit 0
}
trap shutdown SIGINT SIGTERM

mkdir -p "${CONFIG_DIR}/browser-cache" "${CONFIG_DIR}/browser-crashes"

if [[ "$#" -eq 0 ]]; then
  set -- bbx run
fi

parse_runtime_overrides() {
  local args=("$@")
  local i

  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
      --port|-p)
        if (( i + 1 < ${#args[@]} )); then
          export PORT="${args[$((i + 1))]}"
        fi
        ;;
      --port=*)
        export PORT="${args[$i]#*=}"
        ;;
      --hostname|-h)
        if (( i + 1 < ${#args[@]} )); then
          export BBX_HOSTNAME="${args[$((i + 1))]}"
        fi
        ;;
      --hostname=*)
        export BBX_HOSTNAME="${args[$i]#*=}"
        ;;
    esac
  done
}

should_refresh_setup() {
  [[ "${1:-}" == "bbx" ]] || return 1

  case "${2:-}" in
    run|start|restart|cf-run|cf-start|tor-run|tor-start|zt-run|zt-start|ng-run|ng-start|win9x-run|win9x-start)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ "${1:-}" == "bbx" ]]; then
  parse_runtime_overrides "${@:3}"
fi

if is_truthy "${BBX_SETUP_ON_RUN:-true}" && should_refresh_setup "$@"; then
  if [[ -z "${LICENSE_KEY:-}" ]]; then
    echo "[browserbox] ERROR: LICENSE_KEY is required at runtime." >&2
    echo "[browserbox] Run with: docker run -e LICENSE_KEY=... -p ${PORT}:${PORT} <image>" >&2
    exit 2
  fi

  echo "[browserbox] refreshing setup and login token on ${BBX_HOSTNAME}:${PORT}"
  bbx stop >/dev/null 2>&1 || true
  rm -f "${CONFIG_DIR}/login.link"
  BBX_NONINTERACTIVE=true bbx setup \
    --port "${PORT}" \
    --hostname "${BBX_HOSTNAME}" \
    --backend "${BBX_BACKEND}"
fi

case "${1:-} ${2:-}" in
  "bbx run"|"bbx start"|"bbx restart")
    echo "[browserbox] launching: $*"
    "$@"
    if [[ -f "${CONFIG_DIR}/login.link" ]]; then
      echo "[browserbox] login link: $(<"${CONFIG_DIR}/login.link")"
    fi
    if is_truthy "${BBX_KEEP_CONTAINER_ALIVE:-true}"; then
      echo "[browserbox] command returned; keeping container alive until stopped"
      while true; do
        sleep 3600 &
        wait $!
      done
    fi
    ;;
  *)
    exec "$@"
    ;;
esac
SCRIPT
chmod +x /usr/local/bin/browserbox-entrypoint.sh
EOF

EXPOSE 8080

USER bbuser
WORKDIR /home/bbuser

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/browserbox-entrypoint.sh"]
CMD ["bbx", "run"]
