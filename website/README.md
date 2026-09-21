# Safernotes website

Static marketing website for Safernotes. No framework, no build step, no dev
server required.

## Files

- `index.html`: product landing page with desktop/mobile preview, security, offline use, and self-hosting
- `downloads.html`: device-aware download recommendations for web, Android, and iOS
- `docs.html`: installation, self-hosting, operations, troubleshooting, and Q&A
- `downloads.js`: local device detection and platform tab switching
- `assets/product-desktop.png`: real desktop product screenshot
- `assets/product-mobile.png`: real mobile product screenshot
- `privacy.html`: privacy information for offline and self-hosted operation
- `impressum.html`: legal notice with operator and business details
- `terms.html`: open-source software usage information
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

The website links to the Google Play listing and also offers a direct Android
APK at `/downloads/safernotes-android.apk`. The Play Store release workflow is
handled from `frontend/` and produces an `.aab` for upload to Play Console.

## Deployment

The folder can be deployed as static files on providers such as Cloudflare Pages,
Netlify, Vercel static hosting, S3-compatible object storage, or any ordinary
web server.
