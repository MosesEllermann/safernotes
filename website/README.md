# Safernotes website

Static product website, installation guide and FAQ. No build step is required.
Open `index.html` locally or serve this directory with a static web server.

Deploy the complete contents of this directory together, including `docs.html`
and `styles.css`. Uploading only the homepage will leave documentation links
broken or keep older layouts in use. After deployment, check `/docs.html` and
`/docs.html#faq`, and invalidate cached HTML in your hosting/CDN if needed.
The shared navigation remains visible on mobile; the footer links wrap within
the viewport.

- `index.html`: product overview and download links.
- `downloads.html`: platform availability and installation links.
- `docs.html`: installation, Docker configuration, operations and FAQ.
- `privacy.html`, `terms.html`, `impressum.html`: operator-neutral templates.
- `styles.css`: shared responsive styles.

Before publishing your own website, complete the operator information and adapt
the privacy and usage pages to your installation. The landing page includes
the supplied desktop and Android screenshots in `assets/product-desktop.png`
and `assets/product-mobile.png`. Their visible note content is part of the
published website; review replacement screenshots before distributing them.

The Android APK is a separate release artifact. Place a signed release at
`downloads/safernotes-android.apk` when deploying a site that offers direct APK
downloads. The repository links identify the upstream project; forks can replace
them with their own project links.
