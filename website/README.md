# Safernotes website

Static marketing website for Safernotes. No framework, no build step, no dev
server required.

## Files

- `index.html`: product landing page with desktop/mobile preview, platform availability, security, pricing, and CTA
- `downloads.html`: device-aware download recommendations for web, Android, and iOS
- `downloads.js`: local device detection and platform tab switching
- `assets/product-desktop.png`: real desktop product screenshot
- `assets/product-mobile.png`: real mobile product screenshot
- `privacy.html`: privacy policy with hosting, email, and Creem disclosures
- `impressum.html`: legal notice with operator and business details
- `terms.html`: product and subscription terms, including Creem checkout terms
- `styles.css`: shared responsive design system

## Preview

Open `index.html` directly in a browser:

```text
website/index.html
```

All links between the static pages are relative and work from the filesystem.

## Legal To-dos

Obtain a final legal review of the Impressum, privacy policy, and product terms
before enabling live payments.

The website can still link to a direct Android beta APK at
`/downloads/safernotes-android.apk`. The Play Store release workflow is handled
from `frontend/` and produces an `.aab` for upload to Play Console.

## Deployment

The folder can be deployed as static files on providers such as Cloudflare Pages,
Netlify, Vercel static hosting, S3-compatible object storage, or any ordinary
web server.
