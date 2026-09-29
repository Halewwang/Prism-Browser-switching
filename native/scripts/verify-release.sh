#!/bin/zsh
set -euo pipefail

if (( $# < 3 || $# > 4 )); then
  print -u2 "usage: $0 <Prism.app> <version> <build> [Prism.dmg]"
  exit 64
fi

app="$1"
expected_version="$2"
expected_build="$3"
dmg="${4:-}"

if [[ ! -d "$app" ]]; then
  print -u2 "Prism app not found: $app"
  exit 66
fi

verify_app() {
  local candidate="$1"
  local plist="$candidate/Contents/Info.plist"
  local executable="$candidate/Contents/MacOS/Prism"

  [[ -f "$plist" && -x "$executable" ]] || {
    print -u2 "invalid Prism app bundle: $candidate"
    return 1
  }

  local macho
  while IFS= read -r -d '' macho; do
    if file -b "$macho" | grep -q 'Mach-O'; then
      lipo "$macho" -verify_arch arm64
      lipo "$macho" -verify_arch x86_64
    fi
  done < <(find "$candidate/Contents" -type f -print0)

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$expected_version" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$expected_build" ]]
  codesign --verify --deep --strict --verbose=2 "$candidate"
  codesign -d --verbose=4 "$candidate" 2>&1 | grep -q 'flags=.*runtime'
  spctl --assess --type execute --verbose=4 "$candidate"
  xcrun stapler validate "$candidate"
}

verify_app "$app"

if [[ -n "$dmg" ]]; then
  [[ -f "$dmg" ]] || {
    print -u2 "Prism DMG not found: $dmg"
    exit 66
  }
  codesign --verify --verbose=2 "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
  xcrun stapler validate "$dmg"

  mount_root="$(mktemp -d "${TMPDIR:-/tmp}/prism-release-mount.XXXXXX")"
  mounted=false
  cleanup() {
    if [[ "$mounted" == true ]]; then
      hdiutil detach "$mount_root" -quiet || true
    fi
    rmdir "$mount_root" || true
  }
  trap cleanup EXIT
  hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount_root" >/dev/null
  mounted=true

  mounted_apps=("${(@f)$(find "$mount_root" -maxdepth 2 -name Prism.app -type d -print)}")
  (( ${#mounted_apps} == 1 )) || {
    print -u2 "DMG must contain exactly one Prism.app"
    exit 65
  }
  verify_app "$mounted_apps[1]"
fi

print "Release verification passed for Prism $expected_version ($expected_build)."
