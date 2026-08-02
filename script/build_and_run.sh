#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_version="$(tr -d '[:space:]' <"$root_dir/arcbox.version")"
runtime_dir="${ARCBOX_DIR:-$root_dir/.build/arcbox-$runtime_version}"
app_bundle="$root_dir/.build/DerivedData-Runnable/Build/Products/Debug/ArcBox.app"
app_binary="$app_bundle/Contents/MacOS/ArcBox"
abctl_binary="$app_bundle/Contents/MacOS/bin/abctl"
daemon_label="com.arcboxlabs.desktop.dev.daemon"

if [[ ! -e "$runtime_dir/.git" ]]; then
  if [[ -n "${ARCBOX_DIR:-}" ]]; then
    echo "error: ARCBOX_DIR is not a git worktree: $runtime_dir" >&2
    exit 1
  fi
  git -C "$root_dir/../arcbox" worktree add --detach "$runtime_dir" "$runtime_version"
fi

runtime_dir="$(cd "$runtime_dir" && pwd -P)"

if [[ "$(git -C "$runtime_dir" rev-parse HEAD)" != "$(git -C "$runtime_dir" rev-parse "$runtime_version^{commit}")" ]]; then
  echo "error: ARCBOX_DIR must be checked out at $runtime_version: $runtime_dir" >&2
  exit 1
fi

if [[ -n "$(git -C "$runtime_dir" status --porcelain --untracked-files=normal)" ]]; then
  echo "error: ARCBOX_DIR has tracked or untracked source changes: $runtime_dir" >&2
  exit 1
fi

export ARCBOX_DIR="$runtime_dir"
export ARCBOX_HOST_TARGET_DIR="$runtime_dir/target"

/usr/bin/pkill -f "$app_binary" >/dev/null 2>&1 || true
/usr/bin/pkill -x "ArcBox Dev" >/dev/null 2>&1 || true
if command -v cargo >/dev/null 2>&1; then
  make -C "$root_dir" build-runnable
elif command -v devenv >/dev/null 2>&1; then
  devenv shell -- make -C "$root_dir" build-runnable
else
  echo "error: cargo is unavailable; install or enter the project devenv shell" >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$app_bundle"
}

case "$mode" in
  run)
    open_app
    ;;
  --debug | debug)
    /usr/bin/lldb -- "$app_binary"
    ;;
  --logs | logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "ArcBox"'
    ;;
  --telemetry | telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.arcboxlabs.desktop"'
    ;;
  --verify | verify)
    /usr/bin/open -n "$app_bundle" --args -hasCompletedOnboarding YES
    for _ in {1..30}; do
      if /usr/bin/pgrep -f "$app_binary" >/dev/null \
        && /bin/launchctl print "gui/$(/usr/bin/id -u)/$daemon_label" >/dev/null 2>&1 \
        && test -S "$HOME/.arcbox-dev/run/arcbox.sock" \
        && "$abctl_binary" --profile development doctor >/dev/null 2>&1; then
        exit 0
      fi
      sleep 1
    done
    echo "error: ArcBox Dev did not become ready within 30 seconds" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
