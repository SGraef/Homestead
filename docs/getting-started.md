# Getting started

Pantria ships as a Docker image. The fastest path is the bundled
`docker-compose.yml`, which brings up MySQL + the Rails app + the Solid
Queue worker. For Unraid users there's a one-click Community Applications
template.

## Requirements

- Docker Desktop or any Compose v2-capable engine.
- 2 GB free RAM (MySQL is the dominant cost).
- For mobile barcode scanning: an HTTPS reverse proxy (or run dev with the
  bundled self-signed cert). Browsers refuse `getUserMedia` over plain HTTP.

## Local dev in 30 seconds

```bash
git clone git@github.com:SGraef/Pantria.git
cd Pantria
cp .env.example .env       # tweak RAILS_MASTER_KEY etc.
docker compose up --build  # first boot also runs db:prepare
```

Open <http://localhost:3000>, click **Sign up**, create the first user.
That user becomes admin of the household it creates.

!!! tip "First-login household"
    Pantria is multi-household out of the box. Your sign-up creates one
    household and makes you admin; invite family members by email from
    `/households`.

## Production

### Unraid (recommended for self-hosters)

A community-template XML lives at
[`unraid/pantria.xml`](https://github.com/SGraef/Pantria/blob/main/unraid/pantria.xml).
Walk-through, env-var reference and MySQL setup notes are in
[`unraid/README.md`](https://github.com/SGraef/Pantria/blob/main/unraid/README.md).

Short version:

1. Provision a MySQL 8.4 container.
2. Drop the template into `templates-user/`.
3. Fill in `APP_HOST` + DB creds + `RAILS_MASTER_KEY`.
4. Point a reverse proxy at the container — Pantria forces `https` in
   production, so terminate TLS at the proxy.

### Plain docker-compose

```yaml
services:
  db:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: change-me
      MYSQL_DATABASE: pantria
      MYSQL_USER: pantria
      MYSQL_PASSWORD: change-me-too
    volumes:
      - mysql_data:/var/lib/mysql

  web:
    image: ghcr.io/sgraef/pantria:latest
    environment:
      RAILS_ENV: production
      DATABASE_HOST: db
      DATABASE_USERNAME: pantria
      DATABASE_PASSWORD: change-me-too
      DATABASE_NAME: pantria
      RAILS_MASTER_KEY: <paste from config/master.key>
      APP_HOST: pantria.your-domain.tld
    ports:
      - "3000:3000"
    depends_on: [db]

volumes:
  mysql_data:
```

## Configuration

Notable env vars beyond the basics:

| Variable                             | Purpose                                                   |
| ------------------------------------ | --------------------------------------------------------- |
| `APP_HOST`                           | Public hostname; used by mailer + URL helpers             |
| `RAILS_MASTER_KEY`                   | Decrypts `config/credentials/production.yml.enc`          |
| `SMTP_ADDRESS` / `SMTP_PORT`         | Outbound mail relay (activation + reset emails)           |
| `SMTP_USERNAME` / `SMTP_PASSWORD`    | Optional — leave unset for unauthenticated relays         |
| `OCR_PREPROCESS`                     | `0` to disable ImageMagick preprocessing of photo receipts |
| `BRING_API_KEY`                      | Override the bundled Bring! API key                       |
| `ANDROID_TWA_PACKAGE` / `_FINGERPRINTS` | Required for the TWA to drop the Chrome URL bar         |

Full reference: see [`.env.example`](https://github.com/SGraef/Pantria/blob/main/.env.example)
and `config/environments/production.rb`.

## Next steps

- [Browse the feature deep dives :material-arrow-right-thin:](features/index.md)
- [Set up the PWA / Android shell :material-arrow-right-thin:](pwa-android.md)
- [Wire up Observability (OpenTelemetry) :material-arrow-right-thin:](observability.md)
