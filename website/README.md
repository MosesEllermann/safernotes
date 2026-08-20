# Safernotes website

Static marketing website for Safernotes. No framework, no build step, no dev
server required.

## Files

- `index.html`: product landing page with desktop/mobile preview, platform availability, security, pricing, and CTA
- `downloads.html`: device-aware download recommendations for web, Android, and iOS
- `downloads.js`: local device detection and platform tab switching
- `assets/app-preview.png`: desktop product image based on the live Safernotes interface
- `assets/app-mobile.png`: mobile product image based on the responsive Flutter layout
- `privacy.html`: professionally structured privacy policy placeholder
- `impressum.html`: professionally structured legal notice placeholder
- `styles.css`: shared responsive design system

## Preview

Open `index.html` directly in a browser:

```text
website/index.html
```

All links between the static pages are relative and work from the filesystem.

## Legal To-dos

Replace or finalize these before publishing the legal pages:

- Impressum provider details
- Datenschutz provider details, legal bases, storage locations, and processor list
- final legal review of all legal pages

The status panels on the legal pages intentionally mark unfinished legal details.

The production workflow builds the current Android beta and publishes it as
`/downloads/safernotes-android.apk`. Play Store, F-Droid, and iOS remain marked
as not yet available until public store listings exist.

## Deployment

The folder can be deployed as static files on providers such as Cloudflare Pages,
Netlify, Vercel static hosting, S3-compatible object storage, or any ordinary
web server.
