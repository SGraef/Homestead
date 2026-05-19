# Pantria on Unraid

`pantria.xml` is a Community Applications template that runs Pantria as a
single Docker container on Unraid. Puma serves the web app on port 3000 and
Solid Queue runs background jobs in-process inside the same Puma (gated by
`SOLID_QUEUE_IN_PUMA=1`).

## Install

1. Provision MySQL 8.4+ (the `mysql:8.4` template from Community
   Applications works). Create the database and a user:

   ```sql
   CREATE DATABASE pantria_production
     CHARACTER SET utf8mb4
     COLLATE utf8mb4_unicode_ci;
   CREATE USER 'pantria'@'%' IDENTIFIED BY 'your-password';
   GRANT ALL ON pantria_production.* TO 'pantria'@'%';
   ```

2. In Unraid's Docker tab, click **Add Container** → paste the template URL:
   `https://github.com/SGraef/pantria/raw/main/unraid/pantria.xml`
   (or copy `pantria.xml` into `/boot/config/plugins/dockerMan/templates-user/`).

3. Fill in the required fields:
   - `DATABASE_HOST` — usually the MySQL container's name.
   - `DATABASE_PASSWORD` — the password you set above.
   - `APP_HOST` — the public hostname your reverse proxy will serve.
   - `RAILS_MASTER_KEY` — contents of the repo's `config/master.key`.

4. Point a reverse proxy (SWAG, Traefik, NPM) at the container's host port
   with a real TLS cert — `force_ssl=true` is on in production, so plain
   HTTP will redirect immediately.

5. First boot runs `rails db:prepare` automatically. The database schema is
   created and the demo seed user (`demo@pantria.local` / `password123`) is
   inserted on an empty DB.

## Notes

- **Active Storage uploads** live in `/app/storage` inside the container,
  mapped to `/mnt/user/appdata/pantria/storage` by default. Back it up.
- **Logs** stream to stdout. Use `docker logs Pantria` or Unraid's log
  viewer.
- **Two-container variant**: if you want to scale the web tier
  horizontally, set `SOLID_QUEUE_IN_PUMA=0` on the web container(s) and
  spin up a second container from the same image with the command
  overridden to `bundle exec rake solid_queue:start`.
