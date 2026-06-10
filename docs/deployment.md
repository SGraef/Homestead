# Deployment

Pantria runs as a Docker image. Three paths, increasing in operational
fanciness:

1. **Unraid** with the bundled Community Apps template.
2. **Plain docker-compose** on any host.
3. **Kubernetes** — DIY, but the image is just a stock Rails app, so
   any Rails-on-K8s recipe works.

## Unraid

A community-template XML lives at
[`unraid/pantria.xml`](https://github.com/SGraef/Pantria/blob/main/unraid/pantria.xml).
Walk-through, env-var reference and MySQL setup notes are in
[`unraid/README.md`](https://github.com/SGraef/Pantria/blob/main/unraid/README.md).

Short version:

1. Provision a MySQL 8.4 container (Unraid CA has one).
2. Drop the Pantria template into `templates-user/`.
3. Fill in `APP_HOST` + DB creds + `RAILS_MASTER_KEY`.
4. Point a reverse proxy at the container — Pantria forces `https` in
   production, so terminate TLS at the proxy (SWAG, NPM, Caddy, …).

The template defaults the Solid Queue worker to the same container as
the web process via `bin/docker-entrypoint`. If your receipt OCR load
gets heavy, split worker into its own container with
`SOLID_QUEUE_DISABLE=1` set on the web container and the entrypoint
override `rake solid_queue:start` on the worker.

## docker-compose

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
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 5s

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
      # Optional SMTP for activation / password-reset emails
      SMTP_ADDRESS: smtp.your-relay.tld
      SMTP_PORT: "587"
      SMTP_DOMAIN: your-domain.tld
      # SMTP_USERNAME / SMTP_PASSWORD only if your relay needs auth
    ports:
      - "3000:3000"
    depends_on:
      db:
        condition: service_healthy

volumes:
  mysql_data:
```

## SMTP

Notable behaviour: with `SMTP_USERNAME` and `SMTP_PASSWORD` both unset
Pantria connects to the relay *unauthenticated*. That's the right
behaviour for local postfix / Mailpit / internal smarthost relays
that don't need login. Set both to enable SMTP-AUTH. `SMTP_DOMAIN`
controls the HELO/EHLO greeting — set it to a domain you actually own
or strict relays (Mailgun, Postmark, Office 365) will reject your mail.

## Upgrades

```bash
docker compose pull web
docker compose up -d web
```

Migrations run automatically on boot via `bin/docker-entrypoint`'s
`rails db:prepare` step. There's no battle-tested rollback story —
**snapshot the database and the Active Storage volume before pulling
a new image**.

## Storage volumes

Two stateful directories the image expects:

| Path                       | Contents                          | When to back up                         |
| -------------------------- | --------------------------------- | --------------------------------------- |
| MySQL `/var/lib/mysql`     | All structured data               | Before every upgrade                    |
| App `/app/storage`         | Active Storage uploads (receipts) | Before every upgrade + recurring schedule |

A small daily `mysqldump --single-transaction pantria` plus
`tar zcf storage-$(date +%F).tgz /app/storage` is plenty.

## Health check

`GET /up` returns 200 OK once the database is reachable. Suitable for
reverse-proxy health checks and orchestrator liveness probes. Skips
host authorization (the homepage check fires before `before_action`s
run, so it works behind any proxy).

## Image registry

CI publishes to GitHub Container Registry on every push to main:

```
ghcr.io/sgraef/pantria:latest
ghcr.io/sgraef/pantria:main
ghcr.io/sgraef/pantria:<commit-sha>
```

Pin to a SHA for production; `:latest` is fine for personal use but
you'll auto-roll on every push.

## CI gates

The GitHub Actions pipeline (`.github/workflows/ci.yml`) gates the
image build on:

- RuboCop (style)
- Sorbet (type-check)
- RSpec (unit / model / request specs against MySQL 8.4 service)
- Cypress (full e2e stack via docker-compose.test.yml)

RuboCop and Sorbet are `continue-on-error: true` — they surface
warnings in the run summary but don't block the build. RSpec and
Cypress are required.
