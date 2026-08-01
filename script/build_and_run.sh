#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$root_dir/.build/DerivedData-Runnable/Build/Products/Debug/ArcBox.app"
app_binary="$app_bundle/Contents/MacOS/ArcBox"
abctl_binary="$app_bundle/Contents/MacOS/bin/abctl"
daemon_label="com.arcboxlabs.desktop.dev.daemon"

/usr/bin/pkill -f "$app_binary" >/dev/null 2>&1 || true
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
    open_app
    for _ in {1..30}; do
      if /usr/bin/pgrep -f "$app_binary" >/dev/null \
        && /bin/launchctl print "gui/$(/usr/bin/id -u)/$daemon_label" >/dev/null 2>&1 \
        && test -S "$HOME/.arcbox-dev/run/arcbox.sock" \
        && "$abctl_binary" --profile development info >/dev/null 2>&1; then
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
