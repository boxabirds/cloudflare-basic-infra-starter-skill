# Deployment Scripts

## Script Structure

A deploy script should follow this sequence:

1. **Pre-checks** -- uncommitted changes, correct branch
2. **Version management** -- increment, tag
3. **Migration safety** -- scan for dangerous patterns
4. **Apply migrations** -- atomically before code deploy
5. **Deploy worker** -- with retry logic
6. **Health verification** -- confirm the deploy succeeded
7. **Deploy auxiliary services** -- admin worker, frontend
8. **Record deployment** -- tags, CSV log, GitHub deployment

## Migration Safety Scan

Before deploying, scan all pending migrations for dangerous SQL patterns. Block production deploys; warn on staging.

```bash
#!/bin/bash
check_migration_safety() {
  local env="$1"
  local exit_on_danger="$2"  # "block" or "warn"

  local DANGEROUS_PATTERNS=(
    "CHECK ("
    "DROP TABLE"
    "TRUNCATE TABLE"
    "ALTER TABLE.*MODIFY"
    "ALTER TABLE.*CHANGE"
    "ADD CONSTRAINT"
    "DROP CONSTRAINT"
  )

  local found_danger=false

  for migration in migrations/*.sql; do
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
      if grep -qiE "$pattern" "$migration"; then
        echo "WARNING: $migration contains dangerous pattern: $pattern"
        found_danger=true
      fi
    done
  done

  if [ "$found_danger" = true ] && [ "$exit_on_danger" = "block" ]; then
    echo "BLOCKED: Dangerous migration patterns found. Fix before deploying to $env."
    exit 1
  fi
}
```

## Idempotency Check

Query the health endpoint for the currently deployed SHA. Skip deployment if it matches.

```bash
get_deployed_sha() {
  local base_url="$1"
  curl -s "$base_url/health" | jq -r '.git_sha_full // empty'
}

check_already_deployed() {
  local base_url="$1"
  local target_sha="$2"

  local deployed_sha
  deployed_sha=$(get_deployed_sha "$base_url")

  if [ "$deployed_sha" = "$target_sha" ]; then
    echo "Already deployed: $target_sha"
    return 0
  fi
  return 1
}
```

## Retry with Backoff

Wrap `wrangler deploy` in a retry helper. Cloudflare API occasionally has transient failures.

```bash
retry_command() {
  local max_attempts="$1"
  local delay="$2"
  shift 2
  local cmd=("$@")

  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "${cmd[@]}"; then
      return 0
    fi

    echo "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done

  echo "All $max_attempts attempts failed."
  return 1
}

# Usage
retry_command 3 5 wrangler deploy --env production
```

## Health Verification

After deploying, confirm the worker is running the expected version.

```bash
verify_deploy() {
  local base_url="$1"
  local expected_version="$2"
  local max_wait=30
  local elapsed=0

  while [ $elapsed -lt $max_wait ]; do
    local deployed_version
    deployed_version=$(curl -s "$base_url/health" | jq -r '.version // empty')

    if [ "$deployed_version" = "$expected_version" ]; then
      echo "Verified: $deployed_version deployed"
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "FAILED: Expected $expected_version but got $deployed_version after ${max_wait}s"
  return 1
}
```

## Version Tagging

Use two types of tags:

```bash
# Semantic version tag (marks a release)
git tag "v1.2.0"
git push origin "v1.2.0"

# Deployment timestamp tag (records when a deploy happened)
DEPLOY_TAG="deploy/prod/$(date +%Y%m%d-%H%M%S)"
git tag "$DEPLOY_TAG"
git push origin "$DEPLOY_TAG"
```

## Deployment Logging

Append every deployment to a CSV file for audit trail.

```bash
log_deployment() {
  local log_file="docs/ops/deployment-log.csv"
  local deploy_id="$1"
  local operator="$2"
  local git_sha="$3"
  local status="$4"
  local version="$5"

  # Create header if file doesn't exist
  if [ ! -f "$log_file" ]; then
    echo "deploy_id,operator,git_sha,timestamp,status,version" > "$log_file"
  fi

  echo "$deploy_id,$operator,$git_sha,$(date -u +%Y-%m-%dT%H:%M:%SZ),$status,$version" >> "$log_file"
}
```

## Complete Deploy Script Skeleton

See [../assets/deploy.sh.template](../assets/deploy.sh.template) for a complete starter script.

## Staging vs Production Differences

| Concern | Staging | Production |
|---------|---------|------------|
| Migration safety | Warn, prompt to continue | Block and exit |
| Interactive | Can be automated | Must be interactive (terminal check) |
| Version tag | Created during deploy | Must exist before deploy |
| Auto-commit | Optional | Required (deploy artifacts) |
