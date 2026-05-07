# syntax=docker/dockerfile:1.7
# -----------------------------------------------------------------------------
# Pantria — multi-stage Dockerfile producing a minimized production image.
# Build stages:
#   1. base    — slim Ruby with the OS deps Rails needs at runtime
#   2. build   — installs gems with build toolchain, precompiles assets
#   3. runtime — copies only the artifacts needed to serve traffic
# -----------------------------------------------------------------------------
ARG RUBY_VERSION=3.3.6
ARG NODE_VERSION=20

# ----- 1. base ---------------------------------------------------------------
FROM ruby:${RUBY_VERSION}-slim-bookworm AS base

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    PATH=/app/bin:$PATH

WORKDIR /app

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      curl ca-certificates default-libmysqlclient-dev libjemalloc2 tzdata \
      imagemagick poppler-utils \
      tesseract-ocr tesseract-ocr-eng tesseract-ocr-deu \
 && rm -rf /var/lib/apt/lists/*

# ----- 2. build --------------------------------------------------------------
FROM base AS build

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential git pkg-config libyaml-dev curl \
 && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
RUN bundle install --jobs 4 \
 && bundle exec bootsnap precompile --gemfile \
 && rm -rf /usr/local/bundle/cache /usr/local/bundle/ruby/*/cache

COPY . .
RUN bundle exec bootsnap precompile app/ lib/ config/

# Asset precompile uses a placeholder secret so it doesn't require real creds.
RUN SECRET_KEY_BASE=DUMMY DATABASE_HOST=localhost DATABASE_USERNAME=u DATABASE_PASSWORD=p \
    bundle exec rails assets:precompile

# ----- 3. runtime ------------------------------------------------------------
FROM base AS runtime

RUN groupadd --system --gid 1000 pantria \
 && useradd  --system --uid 1000 --gid pantria --create-home --shell /bin/bash pantria

COPY --from=build --chown=pantria:pantria /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=pantria:pantria /app /app

USER pantria

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://localhost:3000/up || exit 1

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
