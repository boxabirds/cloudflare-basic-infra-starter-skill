# Wrangler Multi-Environment Configuration

## Structure

A single `wrangler.toml` with three sections: base (local dev), staging, and production. Each environment gets its own D1 database, KV namespaces, and environment variables.

```toml
name = "my-worker"
main = "dist/index.js"
compatibility_date = "2024-12-01"
compatibility_flags = ["nodejs_compat"]

[build]
command = "node build.js"
watch_dir = "src"

# ============================================
# Local Development (base config)
# ============================================
[[d1_databases]]
binding = "DB"
database_name = "my-app-local"
database_id = "local"

[[kv_namespaces]]
binding = "SESSION_KV"
id = "local-session-kv"

[vars]
ENVIRONMENT = "local"
BASE_URL = "http://localhost:8787"

# ============================================
# Production Environment
# ============================================
[env.production]
name = "my-worker-prod"
logpush = true

[env.production.observability]
enabled = true

[env.production.observability.logs]
enabled = true
invocation_logs = true

[env.production.vars]
ENVIRONMENT = "production"
BASE_URL = "https://api.example.com"
WEB_APP_URL = "https://app.example.com"
COOKIE_DOMAIN = ".example.com"
# Secrets: set via `wrangler secret put <NAME> --env production`
# GITHUB_APP_CLIENT_ID, GITHUB_APP_CLIENT_SECRET, etc.

[[env.production.d1_databases]]
binding = "DB"
database_name = "my-app-prod"
database_id = "<your-prod-d1-id>"

[[env.production.kv_namespaces]]
binding = "SESSION_KV"
id = "<your-prod-kv-id>"

[[env.production.routes]]
pattern = "api.example.com/*"
zone_name = "example.com"

# ============================================
# Staging Environment
# ============================================
[env.staging]
name = "my-worker-staging"
logpush = true

[env.staging.observability]
enabled = true

[env.staging.observability.logs]
enabled = true
invocation_logs = true

[env.staging.vars]
ENVIRONMENT = "staging"
BASE_URL = "https://staging-api.example.com"
WEB_APP_URL = "https://staging-app.example.com"

[[env.staging.d1_databases]]
binding = "DB"
database_name = "my-app-staging"
database_id = "<your-staging-d1-id>"

[[env.staging.kv_namespaces]]
binding = "SESSION_KV"
id = "<your-staging-kv-id>"
```

## Key Principles

### Secrets Never in [vars]

Use `wrangler secret put` per environment for anything sensitive:

```bash
wrangler secret put GITHUB_APP_CLIENT_SECRET --env production
wrangler secret put GITHUB_APP_CLIENT_SECRET --env staging
```

Secrets are encrypted at rest and only available to the running worker. They don't appear in `wrangler.toml` or version control.

### Each Environment Gets Its Own D1

Never share a D1 database between environments. Local dev uses `database_id = "local"` which creates a SQLite file in `.wrangler/state/`.

### Observability in Non-Local Environments

Enable `logpush` and `observability.logs` only in staging and production. Local dev logs go to the terminal.

### Route Patterns

Production workers need explicit route patterns to bind to a custom domain:

```toml
[[env.production.routes]]
pattern = "api.example.com/*"
zone_name = "example.com"
```

Without this, the worker is only accessible at `my-worker-prod.<account>.workers.dev`.

## Creating D1 Databases

```bash
# Create production database
wrangler d1 create my-app-prod
# Output: database_id = "abc123..."  <-- put this in wrangler.toml

# Create staging database
wrangler d1 create my-app-staging
```

## Creating KV Namespaces

```bash
wrangler kv:namespace create SESSION_KV
# Output: id = "def456..."
```

## Local Development

```bash
# Start local worker with Miniflare
wrangler dev

# Apply migrations locally
wrangler d1 migrations apply DB --local
```

Local D1 data lives in `.wrangler/state/v3/d1/`. Delete this directory to reset the local database.
