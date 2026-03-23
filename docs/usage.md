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
```

## Related links

- Main project: https://github.com/BrowserBox/BrowserBox
- License keys: https://browserbox.io
