# browserbox-action

Launch [BrowserBox](https://github.com/BrowserBox/BrowserBox) on a GitHub Actions runner and get back a usable login link.

This action is a thin wrapper around the existing BrowserBox CLI flows. It installs BrowserBox from [browserbox.io](https://browserbox.io), applies your license key, starts the service, and returns the resulting URL as an action output.

BrowserBox requires a valid license key. You can get one at [browserbox.io](https://browserbox.io).

## Status

`browserbox-action` v1 is intentionally narrow:

- Linux runners only
- `tunnel: none`
- `tunnel: cloudflare`
- `tunnel: tor`
- ZeroTier is intentionally excluded from v1

The repo is kept minimal so it can stay compatible with GitHub Action publishing requirements for a dedicated public action repository.

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
          port: 8080

      - name: Print BrowserBox URL
        run: |
          echo "Login link: ${{ steps.browserbox.outputs.login-link }}"
          echo "Base URL:   ${{ steps.browserbox.outputs.base-url }}"
```

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `license-key` | Yes | none | BrowserBox license key from [browserbox.io](https://browserbox.io) |
| `tunnel` | No | `none` | `none`, `cloudflare`, or `tor` |
| `port` | No | `8080` | Main BrowserBox service port |
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

## Supported modes

### `tunnel: none`

Runs:

```bash
bbx setup --port <port> --hostname <hostname>
bbx start --port <port> --hostname <hostname>
```

This is the local runner mode. It is useful when later steps in the same job will talk to BrowserBox directly.

### `tunnel: cloudflare`

Runs:

```bash
bbx cf-run --background --port <port>
```

This is the easiest public demo path for v1.

### `tunnel: tor`

Runs:

```bash
bbx setup --port <port> --hostname <hostname>
bbx tor-run --no-darkweb
```

For v1 this action uses the onion-service path only. It does not enable the "browse outward over Tor" mode.

## Ubuntu notes

This action is written for GitHub-hosted Ubuntu runners in v1.

If the runner is missing prerequisites, the install step uses `apt-get` to install:

- `curl`
- `jq`
- `sudo`
- `vim-common` for `xxd`

## Documentation

- Main BrowserBox project: [github.com/BrowserBox/BrowserBox](https://github.com/BrowserBox/BrowserBox)
- BrowserBox website and licensing: [browserbox.io](https://browserbox.io)
- Additional examples: [docs/usage.md](docs/usage.md)

## Limitations

- GitHub runners are ephemeral. Your BrowserBox session only lives as long as the job and runner do.
- This action does not yet implement ZeroTier.
- This action does not currently provide a cleanup/post step. Runner teardown is relied on for v1.

## License

This repository does not grant any license to BrowserBox itself. BrowserBox usage requires a valid license key from [browserbox.io](https://browserbox.io).
