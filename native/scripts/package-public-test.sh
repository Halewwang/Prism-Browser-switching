#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "usage: $0 <version> <build>"
  exit 64
fi

version="$1"
build="$2"
script_dir="${0:A:h}"
native_root="${script_dir:h}"
output_root="$native_root/build/release/$version-$build"
derived_data="$native_root/build/PublicTestReleaseData"
signing_key="${PRISM_UPDATE_SIGNING_KEY:-}"
[[ -n "$signing_key" && -f "$signing_key" ]] || {
  print -u2 "PRISM_UPDATE_SIGNING_KEY must identify the protected update signing key."
  exit 78
}
expected_public_key="$(sed -n 's/.*static let publicKeyBase64 = "\([^"]*\)".*/\1/p' "$native_root/PrismNative/Updates/PrismUpdateTrust.swift")"
actual_public_key="$(/usr/bin/swift "$native_root/scripts/sign-update.swift" public-key "$signing_key")"
[[ "$actual_public_key" == "$expected_public_key" ]] || {
  print -u2 "Update key does not match the public key embedded in Prism."
  exit 78
}
[[ ! -e "$output_root" ]] || {
  print -u2 "release output already exists: $output_root"
  exit 73
}

cd "$native_root"
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-PublicTest \
  -configuration Release -derivedDataPath "$derived_data" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" build

built_app="$derived_data/Build/Products/Release/Prism.app"
[[ -d "$built_app" ]]
staging="$(mktemp -d "${TMPDIR:-/tmp}/prism-public-test.XXXXXX")"
cleanup() { rm -rf "$staging" }
trap cleanup EXIT
ditto --norsrc --noextattr "$built_app" "$staging/Prism.app"
codesign --force --sign - --options runtime --timestamp=none \
  "$staging/Prism.app/Contents/Helpers/PrismUpdateInstaller"
codesign --force --sign - --options runtime --timestamp=none \
  --preserve-metadata=entitlements,requirements "$staging/Prism.app"
zsh scripts/verify-public-test.sh "$staging/Prism.app" "$version" "$build"
python3 scripts/smoke-public-test-launch.py "$staging/Prism.app"
ln -s /Applications "$staging/Applications"

mkdir -p "$output_root"
dmg_name="Prism-$version-universal-test.dmg"
dmg="$output_root/$dmg_name"
hdiutil create -volname Prism -srcfolder "$staging" -format UDZO "$dmg"
zsh scripts/verify-public-test.sh "$staging/Prism.app" "$version" "$build" "$dmg"

cd "$output_root"
digest="$(shasum -a 256 "$dmg_name" | awk '{print $1}')"
print -r -- "$digest  $dmg_name" > SHA256SUMS.txt
/usr/bin/swift "$native_root/scripts/sign-update.swift" sign "$signing_key" "$dmg" "$version" "$output_root" 15.0
/usr/bin/swift "$native_root/scripts/sign-update.swift" verify "$expected_public_key" "$output_root/update-manifest.json" "$output_root/update-manifest.sig"
print "Verified public-test artifacts are in: $output_root"
