#!/usr/bin/env bash
set -euo pipefail

frontend_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$frontend_dir/.." && pwd)"
logo_source="$repo_dir/website/assets/safernotes-logo.svg"
app_icon_source="$frontend_dir/assets/safernotes-app-icon.svg"

render() {
  local source="$1"
  local size="$2"
  local destination="$3"
  mkdir -p "$(dirname "$destination")"
  /usr/bin/sips -z "$size" "$size" -s format png "$source" \
    --out "$destination" >/dev/null
}

render_opaque() {
  local source="$1"
  local size="$2"
  local destination="$3"
  local temporary
  temporary="$(mktemp -t safernotes-icon).jpg"
  mkdir -p "$(dirname "$destination")"
  /usr/bin/sips -z "$size" "$size" -s format jpeg -s formatOptions 100 \
    "$source" --out "$temporary" >/dev/null
  /usr/bin/sips -s format png "$temporary" --out "$destination" >/dev/null
  rm -f "$temporary"
}

render "$logo_source" 256 "$frontend_dir/assets/safernotes-logo.png"

render "$logo_source" 32 "$repo_dir/website/assets/favicon-32.png"
render "$app_icon_source" 180 "$repo_dir/website/assets/apple-touch-icon.png"
render "$app_icon_source" 192 "$repo_dir/website/assets/icon-192.png"
render "$app_icon_source" 512 "$repo_dir/website/assets/icon-512.png"

cp "$logo_source" "$frontend_dir/web/icons/safernotes-logo.svg"
render "$logo_source" 32 "$frontend_dir/web/favicon.png"
render "$app_icon_source" 192 "$frontend_dir/web/icons/Icon-192.png"
render "$app_icon_source" 512 "$frontend_dir/web/icons/Icon-512.png"
render "$app_icon_source" 192 "$frontend_dir/web/icons/Icon-maskable-192.png"
render "$app_icon_source" 512 "$frontend_dir/web/icons/Icon-maskable-512.png"

render "$logo_source" 48 "$frontend_dir/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
render "$logo_source" 72 "$frontend_dir/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
render "$logo_source" 96 "$frontend_dir/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
render "$logo_source" 144 "$frontend_dir/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
render "$logo_source" 192 "$frontend_dir/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

ios_icons="$frontend_dir/ios/Runner/Assets.xcassets/AppIcon.appiconset"
render_opaque "$app_icon_source" 20 "$ios_icons/Icon-App-20x20@1x.png"
render_opaque "$app_icon_source" 40 "$ios_icons/Icon-App-20x20@2x.png"
render_opaque "$app_icon_source" 60 "$ios_icons/Icon-App-20x20@3x.png"
render_opaque "$app_icon_source" 29 "$ios_icons/Icon-App-29x29@1x.png"
render_opaque "$app_icon_source" 58 "$ios_icons/Icon-App-29x29@2x.png"
render_opaque "$app_icon_source" 87 "$ios_icons/Icon-App-29x29@3x.png"
render_opaque "$app_icon_source" 40 "$ios_icons/Icon-App-40x40@1x.png"
render_opaque "$app_icon_source" 80 "$ios_icons/Icon-App-40x40@2x.png"
render_opaque "$app_icon_source" 120 "$ios_icons/Icon-App-40x40@3x.png"
render_opaque "$app_icon_source" 120 "$ios_icons/Icon-App-60x60@2x.png"
render_opaque "$app_icon_source" 180 "$ios_icons/Icon-App-60x60@3x.png"
render_opaque "$app_icon_source" 76 "$ios_icons/Icon-App-76x76@1x.png"
render_opaque "$app_icon_source" 152 "$ios_icons/Icon-App-76x76@2x.png"
render_opaque "$app_icon_source" 167 "$ios_icons/Icon-App-83.5x83.5@2x.png"
render_opaque "$app_icon_source" 1024 "$ios_icons/Icon-App-1024x1024@1x.png"

echo "Generated Safernotes brand icons."
