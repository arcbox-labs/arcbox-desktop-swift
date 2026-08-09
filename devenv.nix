{ pkgs, lib, ... }:

{
  # nixpkgs lags the Homebrew bottles CI installs, and for xcodegen /
  # swift-format / swiftlint the gap changes behaviour: xcodegen refuses
  # project.yml's minimumXcodeGenVersion, and swift-format disagrees with CI
  # about whole files. These stay for convenience, but they are not
  # authoritative — `make lint` and `make generate-xcodeproj` go through
  # scripts/tool.sh, which enforces the floors CI builds against.
  packages = with pkgs; [
    xcodegen
    swift-format
    swiftlint
    prek
    protobuf
  ] ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.apple-sdk_26 ];

  languages.rust = {
    enable = true;
    channel = "stable";
    targets = [ "aarch64-unknown-linux-musl" ];
  };

  enterShell = ''
    if git rev-parse --git-dir >/dev/null 2>&1; then
      hook_path="$(git rev-parse --git-path hooks/pre-commit)"
      if ! grep -q prek "$hook_path" 2>/dev/null; then
        echo "warning: prek git hook is not installed. Run: prek install"
      fi
    fi
  '';
}
