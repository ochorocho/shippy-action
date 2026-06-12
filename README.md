# Setup Shippy Action

A GitHub composite action that installs [shippy](https://github.com/ochorocho/shippy) — a minimal,
opinionated zero-downtime deployment tool for Composer based PHP projects (optimized for TYPO3) — and
optionally runs it. After this action runs, `shippy` is on the `PATH` for all subsequent steps.

Supports Linux and macOS runners (`amd64` and `arm64`). Shippy does not ship Windows builds.

## Usage

Install the latest release:

```yaml
- uses: ochorocho/shippy-action@v0.0.1
```

Install a specific version and deploy:

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Setup shippy
    uses: ochorocho/shippy-action@v0.0.1
    with:
      shippy-version: v0.0.9

  - name: Deploy
    run: shippy deploy production
```

Install and run in a single step via `args`:

```yaml
- uses: ochorocho/shippy-action@v0.0.1
  with:
    shippy-version: latest
    args: deploy production
```

## Inputs

| Name             | Required | Default            | Description                                                                                  |
| ---------------- | -------- | ------------------ | -------------------------------------------------------------------------------------------- |
| `shippy-version` | no       | `latest`           | Release to install. Accepts `latest`, a tag like `v0.0.9`, or a bare version like `0.0.9`.   |
| `args`           | no       | `''`               | Arguments to run shippy with after install (e.g. `deploy production`). Empty = install only. |
| `install-dir`    | no       | `$HOME/.shippy/bin`| Directory the binary is installed into.                                                      |
| `token`          | no       | `${{ github.token }}` | GitHub token used to resolve `latest` and avoid API rate limits.                          |

## Outputs

| Name       | Description                                             |
| ---------- | ------------------------------------------------------- |
| `version`  | The resolved version that was installed (e.g. `0.0.9`). |
| `bin-path` | Absolute path to the installed `shippy` binary.         |

```yaml
- uses: ochorocho/shippy-action@v1
  id: shippy
- run: echo "Installed shippy ${{ steps.shippy.outputs.version }}"
```

## How it works

The action downloads the matching release asset (`shippy-<os>-<arch>`) and its `.checksum` file from the
[shippy releases](https://github.com/ochorocho/shippy/releases), verifies the SHA-256 checksum, installs
the binary, and adds its directory to `GITHUB_PATH`. The download is rejected if the checksum does not match.

## Development

The install logic lives in [`scripts/install.sh`](scripts/install.sh) and is driven entirely by
environment variables, so it can be tested without a runner:

```bash
# Install a pinned version into a temp dir and assert it works
./test/test-install.sh 0.0.9

# Same, for the latest release
./test/test-install.sh latest
```

CI ([`.github/workflows/test.yml`](.github/workflows/test.yml)) runs both the standalone script test and
the composite action across `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, and `macos-15`.

## License

[MIT](LICENSE)
