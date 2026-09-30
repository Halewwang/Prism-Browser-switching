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

verify_app() {
  local candidate="$1"
  local plist="$candidate/Contents/Info.plist"
  local executable="$candidate/Contents/MacOS/Prism"
  [[ -f "$plist" && -x "$executable" ]] || {
    print -u2 "invalid Prism app bundle: $candidate"
    return 1
  }

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$expected_version" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$expected_build" ]]

  # Public tests use GitHub releases. A Sparkle load command is a startup
  # failure under ad hoc hardened-runtime signing, even when Sparkle is idle.
  if otool -L "$executable" | grep -q 'Sparkle.framework'; then
    print -u2 "public test executable must not link Sparkle"
    return 1
  fi
  [[ ! -e "$candidate/Contents/Frameworks/Sparkle.framework" ]] || {
    print -u2 "public test bundle must not embed Sparkle"
    return 1
  }

  local helper="$candidate/Contents/Helpers/PrismUpdateInstaller"
  [[ -x "$helper" && ! -L "$helper" ]] || {
    print -u2 "public test bundle must include its native update installer"
    return 1
  }
  codesign --verify --strict "$helper"
  local helper_signature
  helper_signature="$(codesign -d --verbose=4 "$helper" 2>&1)"
  [[ "$helper_signature" == *"flags="*"runtime"* ]]
  if otool -L "$helper" | grep -q 'Sparkle.framework'; then
    print -u2 "update installer must not link Sparkle"
    return 1
  fi

  local macho count=0
  while IFS= read -r -d '' macho; do
    if file -b "$macho" | grep -q 'Mach-O'; then
      lipo "$macho" -verify_arch arm64
      lipo "$macho" -verify_arch x86_64
      (( count += 1 ))
    fi
  done < <(find "$candidate/Contents" -type f -print0)
  (( count > 0 ))
  codesign --verify --deep --strict "$candidate"
  local signature_details
  signature_details="$(codesign -d --verbose=4 "$candidate" 2>&1)"
  [[ "$signature_details" == *"flags="*"runtime"* ]]
}

verify_app "$app"

if [[ -n "$dmg" ]]; then
  [[ -f "$dmg" ]]
  hdiutil verify "$dmg" >/dev/null
  mount_root="$(mktemp -d "${TMPDIR:-/tmp}/prism-public-test-mount.XXXXXX")"
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
  verify_app "$mount_root/Prism.app"
fi

print "Public test verification passed for Prism $expected_version ($expected_build)."
