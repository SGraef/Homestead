# Contributing

PRs and issues welcome. Homestead is "vibe-coded" — built largely through
LLM pair-programming — so the contribution loop is friendly to anyone
comfortable with that workflow.

## Local setup

```bash
git clone git@github.com:SGraef/Homestead.git
cd Homestead
cp .env.example .env
docker compose up --build
```

The first run boots MySQL, runs `db:prepare`, and starts both the web
and Solid Queue containers.

## Running the test suite

```bash
# Inside the running web container, OR via docker compose run:
docker compose run --rm web bundle exec rspec
docker compose run --rm web bundle exec rubocop --parallel
docker compose run --rm web bundle exec srb tc
```

`docker-compose.test.yml` brings up the full Cypress stack:

```bash
docker compose -f docker-compose.test.yml up \
  --abort-on-container-exit --exit-code-from cypress cypress
```

## CI gates

Every push triggers (`.github/workflows/ci.yml`):

- **rubocop** — style. `continue-on-error: true`.
- **sorbet** — `srb tc`. `continue-on-error: true`.
- **rspec** — fail-blocking. Runs against MySQL 8.4 service container.
- **cypress** — fail-blocking. Brings up the full compose stack.
- **build-image** — only on push to main; publishes to GHCR.

## Conventions

- **Don't add features, refactor, or introduce abstractions beyond
  what the task requires.** A bug fix doesn't need surrounding
  cleanup; a one-shot operation doesn't need a helper.
- **Default to no comments.** Add one when the *why* is non-obvious
  (hidden constraint, workaround, surprising behaviour). Don't
  explain *what* the code does — names already do that.
- **No nostalgia comments.** Don't reference the current task or
  previous behaviour in code comments. That belongs in the PR
  description and rots as the codebase evolves.
- **Specs in `spec/`.** Models, requests, services, jobs each get a
  matching directory. Factory definitions in `spec/factories/`.
- **Translations in `config/locales/{en,de}.yml`.** Keep the two files
  in sync — DE is primary, EN is fallback. The CI doesn't gate this
  but PRs reviewing the diff will catch missing keys.

## Branching

- `main` — protected; merges only via PR.
- Feature branches — `feature/<short-name>` or `fix/<short-name>`.
- Long-lived integration branches (PWA work, OpenTelemetry, …) are
  fine and have shipped via PRs.

## File a good PR

```
Title: ≤ 70 chars, imperative ("Fix X", not "Fixed X" or "Fixes X")

## Summary
What changed and why. Link the issue if there is one.

## Test plan
- [ ] Spec covers the new behaviour
- [ ] Tried it in browser at /some-page
- [ ] Tested DE + EN
```

## Security

If you find a vulnerability, please email instead of opening a public
issue. Contact is on the GitHub profile.

## License

MIT. By contributing you agree the code lands under the same license.
