# Safernotes website

Static product website, installation guide and FAQ. No build step is required.
Open `index.html` locally or serve this directory with a static web server.

Deploy the complete contents of this directory together, including `docs.html`
and `styles.css`. Uploading only the homepage will leave documentation links
broken or keep older layouts in use. After deployment, check `/docs.html` and
`/docs.html#faq`, and invalidate cached HTML in your hosting/CDN if needed.
The shared navigation remains visible on mobile; the footer links wrap within
the viewport.

## Automated upload to SPanel

The `website` Actions workflow checks local links on pull requests. On pushes
to `main` affecting the website, Flutter app or release tooling, it tests the
app, builds a signed release APK and uploads the website together with that APK.
It can also be started manually
via Actions → website → Run workflow (select `main`). It is independent of the
backend CI and uses the `production` GitHub environment, including any
environment approval rules.

Configure repository secrets or secrets in the `production` environment:

- `SPANEL_HOST`, `SPANEL_USER`, `SPANEL_SSH_KEY`: the website SSH account.
- `SPANEL_PORT`: optional; defaults to 22.
- `SPANEL_LANDING_PATH`: the absolute document root for the homepage.
- `SPANEL_KNOWN_HOSTS`: optional verified SSH host-key entry in OpenSSH known_hosts
  format, with `[hostname]:port` for a non-default port. Obtain the host key
  from the hosting provider or verify its fingerprint through their trusted
  console before saving it. If absent or empty, the upload uses `ssh-keyscan`
  automatically, as in the original deployment. That fallback does not
  independently verify the server identity; a pinned entry is more secure.
- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES_BASE64`: the existing
  base64-encoded Android release keystore and signing properties. Keep the same
  signing key for updates to existing direct-download installations.

Use a dedicated SSH account/key restricted to the website directory. Secret
values must stay in GitHub Settings, never in source files. No API, SMTP or
payment secrets are needed. Signing files are decoded outside the checkout and
removed after the build; only the signed APK is passed to the deployment job.
The APK starts without a preset sync server; users can work offline or enter
their own server URL. The app version comes from `frontend/pubspec.yaml`.

The upload includes HTML, CSS, JavaScript, the web manifest and image assets.
It also replaces `downloads/safernotes-android.apk` with the signed artifact
from the same run and compares the public download with the built file. A
failed Android build prevents deployment, leaving the previous download intact.
It does not delete remote files or upload local configuration or Markdown.
Other downloads, `.htaccess` and `.well-known/` stay intact.
Missing deployment secrets fail with their names, never their values. No
legacy `ENABLE_PRODUCTION_DEPLOY` flag is needed for the website workflow.

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

The Android APK is a separate release artifact, not part of the source tree.
For manual deployments, place a signed release at `downloads/safernotes-android.apk`.
The repository links identify the upstream project; forks can replace
them with their own project links.
