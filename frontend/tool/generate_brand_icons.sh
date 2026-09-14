#!/usr/bin/env bash
set -euo pipefail

frontend_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$frontend_dir/.." && pwd)"
round_logo_source="$repo_dir/website/assets/safernotes-logo.svg"
app_icon_source="$frontend_dir/assets/safernotes-app-icon.svg"
app_icon_light_source="$frontend_dir/assets/safernotes-app-icon-light.svg"
maskable_icon_source="$frontend_dir/assets/safernotes-app-icon-maskable.svg"
app_icon_tinted_source="$frontend_dir/assets/safernotes-app-icon-tinted.svg"
logo_black_source="$frontend_dir/assets/safernotes-logo-black.svg"
logo_white_source="$frontend_dir/assets/safernotes-logo-white.svg"

render() {
  local source="$1"
  local height="$2"
  local width="$3"
  local destination="$4"
  mkdir -p "$(dirname "$destination")"
  /usr/bin/sips -z "$height" "$width" -s format png "$source" \
    --out "$destination" >/dev/null
}

render_square() {
  render "$1" "$2" "$2" "$3"
}

render_jpeg() {
  local source="$1"
  local size="$2"
  local destination="$3"
  mkdir -p "$(dirname "$destination")"
  /usr/bin/sips -z "$size" "$size" -s format jpeg -s formatOptions 100 \
    "$source" --out "$destination" >/dev/null
}

render_opaque_png() {
  local source="$1"
  local size="$2"
  local destination="$3"
  local temporary_dir
  local temporary
  temporary_dir="$(mktemp -d -t safernotes-icons)"
  temporary="$temporary_dir/icon.jpg"
  render_jpeg "$source" "$size" "$temporary"
  /usr/bin/sips -s format png "$temporary" --out "$destination" >/dev/null
  rm -f "$temporary"
  rmdir "$temporary_dir"
}

# Monochrome Flutter UI marks. Their native aspect ratio stays intact.
render "$logo_black_source" 300 360 "$frontend_dir/assets/safernotes-logo-black.png"
render "$logo_white_source" 300 360 "$frontend_dir/assets/safernotes-logo-white.png"

# Website and standalone PWA icons.
render_square "$round_logo_source" 32 "$repo_dir/website/assets/favicon-32.png"
render_opaque_png "$app_icon_light_source" 180 "$repo_dir/website/assets/apple-touch-icon.png"
render_square "$app_icon_source" 192 "$repo_dir/website/assets/icon-192.png"
render_square "$app_icon_source" 512 "$repo_dir/website/assets/icon-512.png"
render_square "$maskable_icon_source" 192 "$repo_dir/website/assets/icon-maskable-192.png"
render_square "$maskable_icon_source" 512 "$repo_dir/website/assets/icon-maskable-512.png"

cp "$round_logo_source" "$frontend_dir/web/icons/safernotes-logo.svg"
render_square "$round_logo_source" 32 "$frontend_dir/web/favicon.png"
render_opaque_png "$app_icon_light_source" 180 "$frontend_dir/web/icons/apple-touch-icon.png"
render_square "$app_icon_source" 192 "$frontend_dir/web/icons/Icon-192.png"
render_square "$app_icon_source" 512 "$frontend_dir/web/icons/Icon-512.png"
render_square "$maskable_icon_source" 192 "$frontend_dir/web/icons/Icon-maskable-192.png"
render_square "$maskable_icon_source" 512 "$frontend_dir/web/icons/Icon-maskable-512.png"

# Legacy Android launchers keep the explicitly round artwork. Android 8+
# replaces these with the adaptive vector layers in mipmap-anydpi-v26.
for entry in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${entry%%:*}"
  size="${entry##*:}"
  destination="$frontend_dir/android/app/src/main/res/mipmap-$density"
  render_square "$app_icon_source" "$size" "$destination/ic_launcher.png"
  render_square "$app_icon_source" "$size" "$destination/ic_launcher_round.png"
done

# iOS/iPadOS use one high-resolution source per light, dark, and tinted
# appearance. Xcode creates the device-specific sizes at build time.
ios_icons="$frontend_dir/ios/Runner/Assets.xcassets/AppIcon.appiconset"
# iOS applies its own rounded-rectangle mask. Use full-bleed artwork here so
# no baked-in white corners or a second circular mask remain visible.
render_opaque_png "$maskable_icon_source" 1024 "$ios_icons/Icon-App-1024x1024-light.png"
render_opaque_png "$maskable_icon_source" 1024 "$ios_icons/Icon-App-1024x1024-dark.png"
render_square "$app_icon_tinted_source" 1024 "$ios_icons/Icon-App-1024x1024-tinted.png"

# Store listing artwork derived from the same brand sources.
render_jpeg "$app_icon_light_source" 512 "$frontend_dir/play-store/app-icon-512.jpg"
render "$frontend_dir/play-store/feature-graphic.svg" 500 1024 \
  "$frontend_dir/play-store/feature-graphic.png"

echo "Generated Safernotes brand icons."
