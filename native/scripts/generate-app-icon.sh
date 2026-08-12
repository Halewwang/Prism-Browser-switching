#!/bin/zsh
set -euo pipefail

if (( $# != 0 )); then
    print -u2 "usage: ${0:t} (uses the approved repository-root build/icon.png source)"
    exit 64
fi

native_directory="${0:A:h}/.."
repository_root="$(git -C "$native_directory" rev-parse --show-toplevel)"
source_icon="$repository_root/build/icon.png"
destination_directory="$native_directory/PrismNative/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$source_icon" ]]; then
    print -u2 "error: approved icon source is missing: $source_icon"
    exit 1
fi

dimensions="$(sips -g pixelWidth -g pixelHeight "$source_icon" 2>/dev/null || true)"
width="$(awk '/pixelWidth:/ { print $2 }' <<< "$dimensions")"
height="$(awk '/pixelHeight:/ { print $2 }' <<< "$dimensions")"
if [[ "$width" != "1024" || "$height" != "1024" ]]; then
    print -u2 "error: approved icon source must be exactly 1024x1024 pixels: $source_icon"
    exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/prism-app-icon.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$destination_directory"

typeset -a renditions
renditions=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for rendition in "${renditions[@]}"; do
    filename="${rendition%%:*}"
    pixels="${rendition##*:}"
    sips --resampleHeightWidth "$pixels" "$pixels" "$source_icon" --out "$temporary_directory/$filename" >/dev/null
    mv "$temporary_directory/$filename" "$destination_directory/$filename"
done

cat > "$temporary_directory/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
mv "$temporary_directory/Contents.json" "$destination_directory/Contents.json"
