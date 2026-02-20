# Health and Operations

## Health Endpoint

Every worker should expose a health endpoint that returns deployment metadata. This is used by deploy scripts for verification and by monitoring for uptime checks.

```typescript
if (url.pathname === "/health") {
  return new Response(
    JSON.stringify({
      status: "ok",
      timestamp: new Date().toISOString(),
      version: VERSION,
      environment: env.ENVIRONMENT || "local",
      git_sha: GIT_SHA_SHORT || "dev",
      git_sha_full: GIT_SHA || "dev",
      deployed_at: DEPLOYED_AT || new Date().toISOString(),
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}
```

### Version Injection

Set version metadata at build time. In your build script:

```javascript
// build.js
const define = {
  "process.env.APP_VERSION": JSON.stringify(process.env.APP_VERSION || "dev"),
  "process.env.GIT_SHA": JSON.stringify(
    execSync("git rev-parse HEAD").toString().trim()
  ),
  "process.env.APP_VERSION_SHORT": JSON.stringify(
    execSync("git rev-parse --short HEAD").toString().trim()
  ),
  "process.env.DEPLOYED_AT": JSON.stringify(new Date().toISOString()),
};
```

Or via Wrangler's `[define]` section:

```toml
[define]
APP_VERSION = "'1.2.0'"
GIT_SHA = "'abc123'"
```

## Deployment Logging

Track every deployment in a CSV file for audit trail.

```csv
deploy_id,operator,git_sha,timestamp,status,version
deploy-001,julian,abc123,2025-02-20T15:30:00Z,success,v1.2.0
deploy-002,julian,def456,2025-02-21T10:00:00Z,success,v1.3.0
```

Location: `docs/ops/deployment-log.csv`

## Version Tagging Convention

Two types of git tags:

### Semantic Version Tags

Created when a release is ready. Format: `v{major}.{minor}.{patch}`

```bash
# Increment and tag
./scripts/increment-version.sh --patch
git tag "v1.2.1"
git push origin "v1.2.1"
```

### Deployment Timestamp Tags

Created after a successful deployment. Format: `deploy/{env}/{YYYYMMDD-HHMMSS}`

```bash
git tag "deploy/prod/20250220-153000"
git push origin "deploy/prod/20250220-153000"
```

### Querying Deployments

```bash
# What version is deployed?
curl -s https://api.example.com/health | jq '.version, .git_sha'

# List all production deployments
git tag | grep '^deploy/prod/'

# What tags are in the deployed SHA?
DEPLOYED_SHA=$(curl -s https://api.example.com/health | jq -r '.git_sha_full')
git tag --merged "$DEPLOYED_SHA"
```

## Database Reset (Local Dev)

Script to reset local D1 for a clean slate:

```bash
#!/bin/bash
# scripts/db-reset-local.sh
set -euo pipefail

echo "Resetting local D1 database..."
rm -rf .wrangler/state/v3/d1/
echo "Applying migrations..."
wrangler d1 migrations apply DB --local
echo "Local database reset complete."
```

## Environment Status Check

Quick script to verify all environments:

```bash
#!/bin/bash
# scripts/env-status.sh

check_env() {
  local name="$1"
  local url="$2"

  local response
  response=$(curl -s --max-time 5 "$url/health" 2>/dev/null)

  if [ $? -eq 0 ]; then
    local version=$(echo "$response" | jq -r '.version // "unknown"')
    local sha=$(echo "$response" | jq -r '.git_sha // "unknown"')
    echo "$name: OK (version=$version, sha=$sha)"
  else
    echo "$name: UNREACHABLE"
  fi
}

check_env "Production" "https://api.example.com"
check_env "Staging"    "https://staging-api.example.com"
check_env "Local"      "http://localhost:8787"
```

## Observability

Enable in wrangler.toml for non-local environments:

```toml
[env.production]
logpush = true

[env.production.observability]
enabled = true

[env.production.observability.logs]
enabled = true
invocation_logs = true
```

Query logs via:
- Cloudflare dashboard: Workers & Pages > your worker > Logs
- Workers Observability API (if using the Cloudflare MCP server)
- Logpush to external destination (R2, S3, Datadog, etc.)
