# Development

## Setup

```bash
git clone https://github.com/arcboxlabs/arcbox-desktop.git
cd arcbox-desktop

cp Local.xcconfig.example Local.xcconfig   # set DEVELOPMENT_TEAM
make build
```

`DEVELOPMENT_TEAM` is the only value you have to fill in. The Sentry, PostHog, and OIDC placeholders can
stay as they are — each one is checked for its placeholder at startup, so telemetry and platform sign-in
simply stay off.

| Command | What it does |
|---|---|
| `make build` | Debug, Swift only, no embedded Rust binaries |
| `make test` | full test suite |
| `make format` / `make lint` | swift-format and SwiftLint |
| `make generate-xcodeproj` | run after adding or removing a file |
| `make lint-xtask` / `make test-xtask` | the Rust packaging crate, gated separately |
| `make dmg` | runnable bundle, daemon and agent included |

> **Do not run `xcodebuild` or `xcodegen` directly.** This repo uses devenv, whose Rust toolchain exports
> a nix `CC`/`SDKROOT`/`DEVELOPER_DIR`; a bare `xcodebuild` then fails with `no such module 'SwiftShims'`.
> The Makefile targets run in an allowlisted environment and behave identically inside `devenv shell`, on
> a clean machine, and in CI.

## Running against a real daemon

Swift-only keeps the loop fast, but the app needs a daemon to talk to, so reach for `make dmg` when you
want to actually run it: it builds `arcbox-daemon`, `abctl`, and `arcbox-agent` from `../arcbox` (override
with `ARCBOX_DIR`), signs the daemon with Developer ID, prefetches the guest boot assets, and embeds the
lot.

The Developer ID signature is not optional. The daemon's restricted entitlements
(`com.apple.security.virtualization`, `com.apple.security.hypervisor`, `com.apple.vm.networking`) are only
honored under Developer ID — signed with an Apple Development certificate, launchd kills it in a silent
`OS_REASON_EXEC` loop. If a local daemon refuses to start, re-sign it with `make -C ../arcbox sign-daemon`.

## Bumping the embedded daemon

```bash
make bump-arcbox VERSION=v0.5.6
```

This updates [`arcbox.version`](../arcbox.version) and regenerates the gRPC client atomically, restoring
both if generation fails. CI enforces that they stay in sync with `make verify-arcbox-protobuf`.

## Project layout

```
ArcBox/                    SwiftUI app
├── Views/                 one directory per source: Containers, Images, Machines, Sandboxes, ...
├── ViewModels/            @Observable state
├── Models/                data models
├── Services/              Docker / machine / sandbox event monitors, diagnostics export
├── Integrations/          Docker CLI + context, terminal apps, guest filesystem
├── Components/            reusable UI
└── Theme/                 design tokens

Packages/
├── ArcBoxClient/          gRPC client, DaemonManager (SMAppService), StartupOrchestrator
├── DockerClient/          Docker Engine API over a Unix socket (OpenAPI generated)
├── K8sClient/             Kubernetes API with kubeconfig and exec-based auth
└── ArcBoxAuth/            OAuth/PKCE session and keychain storage

LaunchDaemons/             launchd plist for the daemon
xtask/                     embedding, signing, and packaging (Rust)
```

## Tech stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + `@Observable`, Swift 6 strict concurrency |
| Daemon | gRPC (grpc-swift + protobuf) |
| Docker | OpenAPI-generated client |
| Terminal | SwiftTerm |
| Daemon lifecycle | SMAppService |
| Auto-updates | Sparkle |
| Crash reports and analytics | Sentry, PostHog |

No Combine, no third-party UI frameworks.

## Further reading

[AGENTS.md](../AGENTS.md) carries the rest: code style, and the SwiftUI startup pitfalls we keep
re-learning — `.task(id:)` racing `onChange`, `Bool` flags that should be state enums, and why timing bugs
only show up on the default tab.
