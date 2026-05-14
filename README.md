# Theia for Kubernetes

[![Security: Trivy](https://img.shields.io/badge/security-scanned%20with%20Trivy-blue)](https://github.com/damien-abos/theia-k8s/security)

A custom [Eclipse Theia](https://theia-ide.org/) IDE distribution preconfigured for Kubernetes development. Ships as a Docker image with `kubectl`, `helm`, and the Kubernetes-related VS Code extensions baked in.

Runs in the browser, supports both `amd64` and `arm64` (including Raspberry Pi 4/5).

## Features

- **Theia 1.71** browser-based IDE
- **VS Code extensions** preinstalled: Kubernetes Tools, YAML (Red Hat), JSON, Shell, Markdown
- **CLI tools** included: `kubectl`, `helm`, `git`, `openssh-client`
- **Multi-architecture**: builds for `linux/amd64` and `linux/arm64`
- **Lightweight**: optimized image with dev dependencies pruned

## Quick start

### Pull and run

```bash
docker run -it --rm \
  -p 3000:3000 \
  -v $(pwd)/workspace:/home/project \
  -v ~/.kube:/home/theia/.kube:ro \
  ghcr.io/damien-abos/theia-k8s:latest
```

Open http://localhost:3000 in your browser.

The `~/.kube` mount gives the Kubernetes extension access to your local kubeconfig (read-only).

## Build

### Prerequisites

- Docker with [Buildx](https://docs.docker.com/buildx/working-with-buildx/) enabled
- ~8 GB free RAM during build
- ~10 GB free disk space

### Single-architecture build

```bash
docker build -t theia-k8s:latest .
```

Expected build time: 5–10 minutes on amd64.

### Multi-architecture build (amd64 + arm64)

First-time setup:

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --name multiarch --use
```

Then build and push to a registry:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t /theia-kubernetes:latest \
  --push \
  .
```

Expected build time: 60–90 minutes (arm64 emulation under QEMU is slow).

For a faster arm64 build, build natively on an arm64 host (Apple Silicon Mac, Raspberry Pi 5 8GB, or arm64 cloud instance).

## Project structure
.
├── Dockerfile            # Multi-stage build (build + runtime)
├── package.json          # Theia dependencies and plugin list
├── patch-ripgrep.js      # Workaround for @theia/native-webpack-plugin
└── README.md

## Configuration

### Adding or removing VS Code extensions

Edit the `theiaPlugins` section in `package.json`. Extensions are pulled from [Open VSX](https://open-vsx.org/) (Theia does not use Microsoft's marketplace).

Example to add the Helm extension:

```json
"theiaPlugins": {
  "tim-koehler.helm-intellisense": "https://open-vsx.org/api/tim-koehler/helm-intellisense/0.13.5/file/tim-koehler.helm-intellisense-0.13.5.vsix"
}
```

### Adjusting Theia modules

The `dependencies` section in `package.json` controls which Theia features are bundled. The current list is a minimal set for Kubernetes work. Adding modules increases image size and memory consumption.

Common additions:

- `@theia/scm` and `@theia/git` for Git UI
- `@theia/debug` for debugging support
- `@theia/console` for the integrated developer console

## Resource requirements

### Runtime

| Use case | Recommended memory |
|----------|-------------------|
| Demo / lightweight use | 1 GB |
| Single user, normal workloads | 2 GB |
| Comfortable daily use | 3–4 GB |

To cap container memory (recommended on Raspberry Pi):

```bash
docker run --memory=3g --memory-swap=3g ...
```

### Raspberry Pi notes

| Model | Verdict |
|-------|---------|
| Pi 4 (2 GB) | Not recommended |
| Pi 4 (4 GB) | Usable, allocate 2.5 GB max |
| Pi 4 / Pi 5 (8 GB) | Comfortable |

Building directly on a Pi works but takes 1–3 hours. Cross-compilation from a faster machine via Buildx is strongly preferred.

## Known issues and workarounds

### `@vscode/ripgrep` binary location

Recent versions of `@vscode/ripgrep` ship the binary in platform-specific subpackages (`@vscode/ripgrep-linux-x64`, `@vscode/ripgrep-linux-arm64`, etc.) rather than in `@vscode/ripgrep/bin/` directly. The Dockerfile creates a symlink to bridge this.

### `native-webpack-plugin` resolver

`@theia/native-webpack-plugin` 1.71 uses `require.resolve('@vscode/ripgrep/bin/rg')` which fails on Node 20+ due to stricter package exports resolution. The `patch-ripgrep.js` script rewrites this call to use a direct path. Without this patch, the webpack build fails with `ERR_PACKAGE_PATH_NOT_EXPORTED`.

### `v8-compile-cache` strict resolution

`v8-compile-cache` (a transitive dependency) intercepts `require.resolve` and adds extra strictness. The Dockerfile stubs it out before bundling.

## Development

### Updating Theia

Bump the version in `package.json` for all `@theia/*` packages. Note that newer versions may change how `native-webpack-plugin` works — the patch in `patch-ripgrep.js` may need updating. Test the build before pushing.

### Adding `kubectl` plugins

The image installs `kubectl` from the upstream Kubernetes apt repository. To add plugins, extend the runtime stage:

```dockerfile
RUN kubectl krew install <plugin>
```

(You'll also need to install `krew` first.)

## License

Theia is licensed under [EPL-2.0 OR GPL-2.0-only WITH Classpath-exception-2.0](https://github.com/eclipse-theia/theia/blob/master/LICENSE).

The Kubernetes Tools VS Code extension is licensed under MIT.

This repository's own files (Dockerfile, configuration) are released under [MIT](LICENSE).

## Acknowledgments

- [Eclipse Theia](https://theia-ide.org/) — the IDE framework
- [Open VSX Registry](https://open-vsx.org/) — the open extensions marketplace
- [Vogella blog on Theia](https://vogella.com/blog/theia_getting_started/) — reference material that made this build possible