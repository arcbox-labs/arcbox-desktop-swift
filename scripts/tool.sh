#!/usr/bin/env bash
#
# Resolves a developer tool to a build new enough to agree with CI.
#
# devenv pins these through nixpkgs, which lags well behind the Homebrew
# bottles CI installs — swift-format especially, where the two versions
# disagree about whole files. The result is a formatter that is happy locally
# and a red PR, or a spec that xcodegen refuses to read. So: take the first
# candidate that meets the floor, and say so plainly when there is none.
#
# Floors track what CI installs. Raise them together with .github/workflows.
#
#   scripts/tool.sh <name>              print the path
#   scripts/tool.sh <name> [args...]    run it
set -euo pipefail

name=${1:?usage: tool.sh <name> [args...]}
shift

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

case $name in
xcodegen)
    # project.yml refuses to load on anything older.
    minimum=$(awk '/minimumXcodeGenVersion:/ { print $2 }' "$repo_root/project.yml")
    ;;
swift-format) minimum=603.0.0 ;;
swiftlint) minimum=0.65.0 ;;
*)
    echo "tool.sh: no version floor recorded for '$name'" >&2
    exit 2
    ;;
esac

for candidate in "$name" "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    bin=$(command -v "$candidate" 2>/dev/null) || continue
    # `xcodegen --version` prints "Version: 2.45.4", the others just the number.
    version=$("$bin" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1) || continue
    [ -n "$version" ] || continue
    [ "$(printf '%s\n%s\n' "$minimum" "$version" | sort -V | head -1)" = "$minimum" ] || continue

    if [ "$#" -eq 0 ]; then
        printf '%s\n' "$bin"
    else
        exec "$bin" "$@"
    fi
    exit 0
done

echo "error: no $name >= $minimum on PATH." >&2
echo "  devenv ships an older one; install a current build with: brew install $name" >&2
exit 1
