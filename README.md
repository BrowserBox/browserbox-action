# browserbox-action

Launch [BrowserBox](https://github.com/BrowserBox/BrowserBox) on a GitHub Actions runner and get back a usable login link.

This action is a thin wrapper around the existing BrowserBox CLI flows. It installs BrowserBox from [browserbox.io](https://browserbox.io), applies your license key, starts the service, and returns the resulting URL as an action output.

**Ephemeral Remote Browser:** This action allows you to run BrowserBox on GitHub runner infrastructure and get a public login link using `cf-run`, providing you with an ephemeral remote browser.

BrowserBox requires a valid license key. You can get one at [browserbox.io](https://browserbox.io).

On runners, the action defaults to a minimal runtime footprint:

- `BBX_MINIMAL_MODE=true`
- `BBX_NO_UPDATE=true`

## Status

`browserbox-action` v1 is intentionally narrow:

- Linux runners only
- `tunnel: none`
- `tunnel: cloudflare` (Public login link)
- `tunnel: tor`
- ZeroTier is intentionally excluded from v1

## Quick start

```yaml
name: BrowserBox demo

on:
  workflow_dispatch:

jobs:
  browserbox:
    runs-on: ubuntu-latest
    steps:
      - name: Launch BrowserBox
        id: browserbox
        uses: BrowserBox/browserbox-action@v1
        with:
          license-key: ${{ secrets.BROWSERBOX_LICENSE_KEY }}
          tunnel: cloudflare
          timeout: 60 # Stay alive for 60 minutes
```

## Features

- **Interactive Login Link:** Like `tmate`, the action prints the login link in a loop to the console until the timeout is reached or the job is cancelled.
- **Configurable Timeout:** Control how long the session stays active (default 30m, up to 150m).
- **Step Summary:** Automatically adds the login link and base URL to the GitHub Actions Job Summary.

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `license-key` | Yes | none | BrowserBox license key from [browserbox.io](https://browserbox.io) |
| `tunnel` | No | `none` | `none`, `cloudflare`, or `tor` |
| `timeout` | No | `30` | Maximum run time in minutes (max 150) |
| `port` | No | `8080` | Main BrowserBox service port |
| `service-mode` | No | `minimal` | `minimal` runs only `bb-main`; `full` runs all BrowserBox services |
| `hostname` | No | `localhost` | Used for local setup when `tunnel=none` |
| `email` | No | `actions@browserbox.io` | Email used during setup when needed |
| `install-url` | No | `https://browserbox.io/install.sh` | Installer source |
| `status-mode` | No | empty | Optional `STATUS_MODE` override |
| `install-doc-viewer` | No | `false` | Whether BrowserBox should install doc viewer dependencies |
| `create-summary` | No | `true` | Whether to write a GitHub step summary |

## Outputs

| Output | Description |
| --- | --- |
| `login-link` | BrowserBox login link |
| `base-url` | BrowserBox base URL with the token removed |
| `tunnel` | Effective tunnel mode |
| `service-mode` | Effective BrowserBox service mode |

## Documentation

- Main BrowserBox project: [github.com/BrowserBox/BrowserBox](https://github.com/BrowserBox/BrowserBox)
- BrowserBox website and licensing: [browserbox.io](https://browserbox.io)
- Additional examples: [docs/usage.md](docs/usage.md)

## Limitations

- GitHub runners are ephemeral. Your BrowserBox session only lives as long as the job and runner do.
- Maximum timeout is 150 minutes.

## License

This repository does not grant any license to BrowserBox itself. BrowserBox usage requires a valid license key from [browserbox.io](https://browserbox.io).
