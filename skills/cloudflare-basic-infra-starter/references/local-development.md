# Local Development: Zero to Running

Complete walkthrough to get a Cloudflare Workers project running locally without touching staging or production.

## Prerequisites

```bash
npm install -g wrangler    # or: brew install wrangler
node --version             # 18+ required
```

## 1. Initialize the Project

```bash
mkdir my-project && cd my-project
npm init -y
npm install --save-dev wrangler @cloudflare/vitest-pool-workers vitest
```

## 2. Configure Wrangler

Copy the starter template and fill in your project name:

```bash
cp /path/to/cloudflare-basic-infra-starter/assets/wrangler.toml.template wrangler.toml
# Edit: replace MY_WORKER and MY_APP with your names
```

The base config (top-level in wrangler.toml) is your local environment. It uses `database_id = "local"` which creates a SQLite file in `.wrangler/state/` -- no remote database needed.

## 3. Write Your First Migration

```bash
mkdir -p migrations
```

Create `migrations/0001_initial_schema.sql`:

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  deleted INTEGER DEFAULT 0,
  deleted_at TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_deleted ON users(deleted);
```

## 4. Apply Migrations Locally

```bash
wrangler d1 migrations apply DB --local
```

This creates the SQLite database in `.wrangler/state/v3/d1/` and runs your migration. No Cloudflare account needed for local dev.

## 5. Create Your Worker Entry Point

Create `src/index.ts`:

```typescript
export interface Env {
  DB: D1Database;
  ENVIRONMENT?: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Health check
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({
        status: "ok",
        timestamp: new Date().toISOString(),
        environment: env.ENVIRONMENT || "local",
      }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Your routes here
    return new Response("Not found", { status: 404 });
  },
};
```

## 6. Start the Worker

```bash
wrangler dev
```

Output:
```
⎔ Starting local server...
[wrangler:inf] Ready on http://localhost:8787
```

Test it:
```bash
curl http://localhost:8787/health
# {"status":"ok","timestamp":"2025-02-20T15:00:00.000Z","environment":"local"}
```

## 7. Start the Frontend (If Applicable)

If you have a Vite frontend, configure the proxy to avoid CORS issues:

```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8787",
        changeOrigin: true,
      },
    },
  },
});
```

```bash
cd apps/web   # or wherever your frontend lives
npm run dev   # Vite starts on http://localhost:5173
```

The frontend calls `/api/*` which Vite proxies to the local worker on port 8787.

## 8. Run Tests

### Unit Tests (vitest pool workers)

```bash
npx vitest run
```

These use Miniflare bindings -- isolated, fast, no network calls.

### E2E Tests (against running worker)

Create `.env.test`:
```bash
TEST_ENDPOINT=http://localhost:8787
```

```bash
# In a separate terminal (worker must be running)
npx vitest run tests/e2e/
```

## 9. Reset Local Database

When you need a clean slate:

```bash
rm -rf .wrangler/state/v3/d1/
wrangler d1 migrations apply DB --local
```

## 10. Next Steps

Once local dev is working:

1. Create remote D1 databases: `wrangler d1 create my-app-staging`
2. Fill in database IDs in `wrangler.toml` staging/production sections
3. Set secrets: `wrangler secret put MY_SECRET --env staging`
4. Deploy to staging: `wrangler deploy --env staging`
5. Verify: `curl https://staging-api.example.com/health`

See [deployment-scripts.md](deployment-scripts.md) for the full deploy workflow with safety checks.
