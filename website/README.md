# Safernotes website

Static marketing website for Safernotes. No framework, no build step, no dev
server required.

## Files

- `index.html`: landing page with hero, product preview, trust section, workflow, pricing, and CTA
- `privacy.html`: professionally structured privacy policy placeholder
- `impressum.html`: professionally structured legal notice placeholder
- `styles.css`: shared responsive design system

## Preview

Open `index.html` directly in a browser:

```text
website/index.html
```

All links between the static pages are relative and work from the filesystem.

## Livegang To-dos

Replace or finalize these before publishing:

- `http://localhost:3000/` app links
- `hello@example.com` contact links
- Impressum provider details
- Datenschutz provider details, legal bases, storage locations, and processor list
- final legal review of all legal pages
- production app URL and production support email
- self-host the free fonts currently loaded from Google Fonts, or replace the
  import with locally hosted font files for production/privacy compliance

The yellow/black `Livegang-TODO` bars and small `TODO` link badges intentionally
mark unfinished production details.

## Deployment

The folder can be deployed as static files on providers such as Cloudflare Pages,
Netlify, Vercel static hosting, S3-compatible object storage, or any ordinary
web server.
