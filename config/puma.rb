# frozen_string_literal: true
# typed: ignore

max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS", max_threads_count)
threads min_threads_count, max_threads_count

worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "development")
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

if ENV["WEB_CONCURRENCY"]
  workers ENV.fetch("WEB_CONCURRENCY", 2)
  preload_app!
end

plugin :tmp_restart

# Solid Queue is started as an explicit background process from
# bin/docker-entrypoint (rather than via `plugin :solid_queue`) so
# worker crashes are visible in container logs instead of swallowed
# by Puma's plugin runtime.
