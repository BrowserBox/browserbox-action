# Usage

## Local runner mode

```yaml
steps:
  - name: Launch BrowserBox locally
    id: browserbox
    uses: BrowserBox/browserbox-action@v1
    with:
      license-key: ${{ secrets.BROWSERBOX_LICENSE_KEY }}
      tunnel: none
      port: 8080
      hostname: localhost
      service-mode: minimal

  - name: Use the login link in a later step
    run: |
      echo "${{ steps.browserbox.outputs.login-link }}"
```

## Cloudflare quick tunnel

```yaml
steps:
  - name: Launch BrowserBox over Cloudflare
    id: browserbox
    uses: BrowserBox/browserbox-action@v1
    with:
      license-key: ${{ secrets.BROWSERBOX_LICENSE_KEY }}
      tunnel: cloudflare
      port: 8080
      service-mode: minimal
```

## Tor onion service

```yaml
steps:
  - name: Launch BrowserBox over Tor
    id: browserbox
    uses: BrowserBox/browserbox-action@v1
    with:
      license-key: ${{ secrets.BROWSERBOX_LICENSE_KEY }}
      tunnel: tor
      port: 8080
      service-mode: minimal
```

## Full multi-service mode

```yaml
steps:
  - name: Launch full BrowserBox service cluster
    id: browserbox
    uses: BrowserBox/browserbox-action@v1
    with:
      license-key: ${{ secrets.BROWSERBOX_LICENSE_KEY }}
      tunnel: none
      port: 8080
      service-mode: full
```

Default launch behavior is:

- `BBX_MINIMAL_MODE=true`
- `BBX_NO_UPDATE=true`

Set `service-mode: full` only if you intentionally need the extra BrowserBox services and have a plan for reaching them.

## Related links

- Main project: https://github.com/BrowserBox/BrowserBox
- License keys: https://browserbox.io
