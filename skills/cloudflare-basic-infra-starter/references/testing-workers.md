# Testing Workers

## Local Development

Start a local worker with Miniflare (built into Wrangler):

```bash
wrangler dev
# Starts on http://localhost:8787
# Uses local SQLite for D1
# KV and other bindings are mocked
```

Local D1 data is stored in `.wrangler/state/v3/d1/`. Delete this directory to reset.

## Test Endpoint Gating

Create test-only endpoints for E2E test setup (seed data, create sessions, provision API keys). Gate them on environment to prevent abuse in production.

```typescript
// In your request handler
if (url.pathname.startsWith("/test/")) {
  if (env.ENVIRONMENT === "production") {
    return new Response(null, { status: 404 });
  }
  return handleTestRoute(request, env);
}
```

Example test endpoints:

```typescript
// POST /test/seed-data -- create test project, users, sample data
// POST /test/create-api-key -- provision an API key for test auth
// POST /test/create-session -- create a session cookie for test auth
// GET  /test/events -- query events for test verification
```

These endpoints should:
- Accept JSON body with the data to create
- Return the created resources (including generated IDs/keys)
- Skip auth checks (they're behind the environment gate)

## Unit Tests with Vitest Pool Workers

Use `@cloudflare/vitest-pool-workers` for unit tests that need Cloudflare bindings.

```typescript
// vitest.config.ts
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          d1Databases: ["DB"],
          kvNamespaces: ["SESSION_KV"],
        },
      },
    },
  },
});
```

```typescript
// tests/example.test.ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";

describe("database", () => {
  it("creates a record", async () => {
    await env.DB.prepare(
      "INSERT INTO users (id, email) VALUES (?, ?)"
    ).bind("test-id", "test@example.com").run();

    const user = await env.DB.prepare(
      "SELECT * FROM users WHERE id = ?"
    ).bind("test-id").first();

    expect(user).toBeTruthy();
    expect(user!.email).toBe("test@example.com");
  });
});
```

**Critical rule**: Unit tests must never connect to remote databases. Use Miniflare's local bindings only.

## E2E Test Setup

Create an `.env.test` file with the test endpoint URL:

```bash
# .env.test
MCP_TEST_ENDPOINT=http://localhost:8787
TEST_API_KEY=test-key-for-local-dev
```

Load it in your test setup:

```typescript
// tests/e2e/setup.ts
import { config } from "dotenv";
import { resolve } from "path";

config({ path: resolve(__dirname, "../../.env.test"), override: true });

export const TEST_ENDPOINT = process.env.MCP_TEST_ENDPOINT!;
export const TEST_API_KEY = process.env.TEST_API_KEY!;
```

## E2E Test Pattern

```typescript
// tests/e2e/health.test.ts
import { TEST_ENDPOINT } from "./setup";
import { describe, it, expect } from "vitest";

describe("health endpoint", () => {
  it("returns ok", async () => {
    const response = await fetch(`${TEST_ENDPOINT}/health`);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe("ok");
    expect(body.environment).toBeDefined();
  });
});
```

## Test Organization

```
workers/my-worker/
├── tests/
│   ├── unit/          # Vitest pool workers, isolated, fast
│   │   ├── db.test.ts
│   │   └── auth.test.ts
│   └── integration/   # Hit local worker via HTTP
│       └── api.test.ts
tests/
└── e2e/               # Full end-to-end against running worker
    ├── setup.ts
    ├── health.test.ts
    └── auth.test.ts
```

## Testing Sequence

1. Run unit tests: `cd workers/my-worker && npm test`
2. Start local server: `wrangler dev`
3. Run E2E tests against local: `npm run test:e2e`
4. Only after local passes: deploy to staging
5. Run E2E tests against staging (change `.env.test` endpoint)
6. Only after staging passes: deploy to production
