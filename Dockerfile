# Use Ruby 3.4official image
FROM ruby:3.4-slim

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock* ./

# Install production dependencies only
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .

# Expose port
EXPOSE 9292

# Set environment to production
ENV RACK_ENV=production

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:9292/health || exit 1

# Run the application
CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
