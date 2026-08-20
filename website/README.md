# Safernotes website

Static marketing website for Safernotes. No framework, no build step, no dev
server required.

## Files

- `index.html`: simple product landing page with app preview, security, pricing, and CTA
- `assets/app-preview.png`: product image based on the live Safernotes interface
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

The notice bars on the legal pages intentionally mark unfinished legal details.

## Deployment

The folder can be deployed as static files on providers such as Cloudflare Pages,
Netlify, Vercel static hosting, S3-compatible object storage, or any ordinary
web server.
