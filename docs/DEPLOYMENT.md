# Safernotes Deployment

Diese Anleitung beschreibt das einfache Produktions-Setup:

- `safernotes.com`: Landingpage auf SPanel
- `app.safernotes.com`: Flutter Web App auf SPanel
- `api.safernotes.com`: Django API auf dem Ubuntu-Host

## 1. DNS

Lege beim DNS-Anbieter diese Records an:

```text
safernotes.com      A      <SPANEL_PUBLIC_IP>
www                 A      <SPANEL_PUBLIC_IP>
app                 A      <SPANEL_PUBLIC_IP>
api                 A      <UBUNTU_HOST_PUBLIC_IP>
```

Falls du IPv6 nutzt, ergänze passende `AAAA` Records. Bis alles live ist, ist eine TTL von `300` Sekunden angenehm.

## 2. SPanel

Lege in SPanel zwei Websites/Subdomains an:

```text
safernotes.com
app.safernotes.com
```

Aktiviere SSL für beide Domains. Notiere dir die absoluten Webroot-Pfade, zum Beispiel:

```text
/home/<user>/domains/safernotes.com/public_html
/home/<user>/domains/app.safernotes.com/public_html
```

Diese Pfade werden später als GitHub Secrets eingetragen:

```text
SPANEL_LANDING_PATH
SPANEL_APP_PATH
```

## 3. Ubuntu-Host Vorbereiten

Installiere Docker, Docker Compose Plugin, Git und Caddy. Danach sollte dein Deploy-User ohne `sudo` Docker nutzen können.

Erstelle die Verzeichnisse:

```sh
sudo mkdir -p /opt/safernotes/app /opt/safernotes/data /opt/safernotes/backups/db
sudo chown -R <deploy-user>:<deploy-user> /opt/safernotes
```

Clone das Repo:

```sh
git clone https://github.com/MosesEllermann/Notizen-App.git /opt/safernotes/app
```

Lege die Produktions-Env außerhalb des Git-Repos an:

```sh
cp /opt/safernotes/app/.env.production.example /opt/safernotes/.env.production
nano /opt/safernotes/.env.production
```

Wichtige Werte:

```env
DJANGO_SETTINGS_MODULE=config.settings.production
DEBUG=False
SECRET_KEY=<langes-zufaelliges-secret>
ALLOWED_HOSTS=api.safernotes.com,127.0.0.1,localhost
CORS_ALLOWED_ORIGINS=https://app.safernotes.com
POSTGRES_PASSWORD=<langes-zufaelliges-db-passwort>
DATABASE_URL=postgres://safernotes:<gleiches-db-passwort>@postgres:5432/safernotes
SAFERNOTES_DATA_DIR=/opt/safernotes/data
SAFERNOTES_API_PORT=8000
```

## 4. API Reverse Proxy

Installiere Caddy auf dem Ubuntu-Host und verwende:

```text
api.safernotes.com {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8000
}
```

Im Repo liegt die Vorlage unter `deploy/caddy/Caddyfile`.

Firewall:

```text
22/tcp   SSH
80/tcp   HTTP fuer Let's Encrypt
443/tcp  HTTPS API
```

Postgres `5432`, Redis `6379` und Django `8000` bleiben nicht öffentlich offen.

## 5. Erster Backend-Start

Auf dem Ubuntu-Host:

```sh
cd /opt/safernotes/app
bash deploy/scripts/deploy_backend.sh /opt/safernotes/app
```

Danach prüfen:

```sh
curl -fsS http://127.0.0.1:8000/api/v1/health/live
curl -fsS https://api.safernotes.com/api/v1/health/live
```

## 6. SSH Keys Für GitHub Actions

Erstelle am besten zwei Deploy-Keys auf deinem lokalen Rechner oder Server:

```sh
ssh-keygen -t ed25519 -C github-actions-spanel-safernotes -f ./github-actions-spanel-safernotes
ssh-keygen -t ed25519 -C github-actions-api-safernotes -f ./github-actions-api-safernotes
```

Füge den jeweiligen `.pub` Inhalt auf SPanel und dem Ubuntu-Host in `~/.ssh/authorized_keys` des Deploy-Users ein.

Die privaten Keys kommen als GitHub Secrets ins Repo.

## 7. GitHub Secrets

In GitHub:

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

Benötigte Secrets:

```text
SPANEL_HOST
SPANEL_USER
SPANEL_SSH_KEY
SPANEL_LANDING_PATH
SPANEL_APP_PATH

API_HOST
API_USER
API_SSH_KEY
API_PROJECT_PATH
```

Optionale Secrets:

```text
SPANEL_PORT
API_PORT
```

Empfohlene Werte:

```text
API_PROJECT_PATH=/opt/safernotes/app
```

Optional als GitHub Variable:

```text
SAFERNOTES_API_BASE_URL=https://api.safernotes.com
ENABLE_PRODUCTION_DEPLOY=true
```

Lasse `ENABLE_PRODUCTION_DEPLOY` weg oder setze es nicht auf `true`, solange DNS, Server und SSH-Secrets noch nicht fertig sind. Der Workflow testet und baut dann weiter, ueberspringt aber den echten Produktions-Deploy.

## 8. Automatisches Deployment

Nach der Einrichtung reicht:

```sh
git push origin main
```

GitHub Actions macht dann:

1. Backend testen
2. Flutter analysieren
3. Flutter Web mit `https://api.safernotes.com` bauen
4. Landingpage zu SPanel kopieren
5. Flutter App zu SPanel kopieren
6. Backend auf Ubuntu aktualisieren
7. Migrationen ausführen
8. API Healthcheck prüfen

Die SPanel-Deploys schuetzen vorhandene `.htaccess`- und `.well-known/`-Dateien, damit SSL-Erneuerungen und Panel-Regeln nicht durch `rsync --delete` entfernt werden.

## 9. Backups

Auf dem Ubuntu-Host:

```sh
PROJECT_DIR=/opt/safernotes/app \
SAFERNOTES_ENV_FILE=/opt/safernotes/.env.production \
SAFERNOTES_BACKUP_DIR=/opt/safernotes/backups/db \
bash /opt/safernotes/app/deploy/scripts/backup_postgres.sh
```

Cron-Beispiel:

```cron
15 3 * * * PROJECT_DIR=/opt/safernotes/app SAFERNOTES_ENV_FILE=/opt/safernotes/.env.production SAFERNOTES_BACKUP_DIR=/opt/safernotes/backups/db /opt/safernotes/app/deploy/scripts/backup_postgres.sh
```

Wenn die Dumps zusätzlich in einen privaten SPanel-Backup-Ordner kopiert werden sollen:

```cron
15 3 * * * PROJECT_DIR=/opt/safernotes/app SAFERNOTES_ENV_FILE=/opt/safernotes/.env.production SAFERNOTES_BACKUP_DIR=/opt/safernotes/backups/db SAFERNOTES_BACKUP_REMOTE_TARGET=<spanel-user>@<spanel-host>:/home/<spanel-user>/private/safernotes-backups/db /opt/safernotes/app/deploy/scripts/backup_postgres.sh
```

Der Zielordner muss außerhalb von `public_html` liegen.
