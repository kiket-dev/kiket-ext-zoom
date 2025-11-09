# frozen_string_literal: true

# Puma configuration file

# Number of workers (processes)
workers ENV.fetch("WEB_CONCURRENCY", 2).to_i

# Threads per worker
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

# Port to bind to
port ENV.fetch("PORT", 9292).to_i

# Environment
environment ENV.fetch("RACK_ENV", "production")

# Preload application for better performance
preload_app!

# Worker timeout
worker_timeout 30

# Allow puma to be restarted by `bin/rails restart` command
plugin :tmp_restart

# Logging
stdout_redirect(
  ENV.fetch("PUMA_STDOUT_LOG", "/dev/stdout"),
  ENV.fetch("PUMA_STDERR_LOG", "/dev/stderr"),
  true
)
