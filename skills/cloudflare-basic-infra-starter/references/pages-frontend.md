# Pages Frontend Deployment

## Setup

Cloudflare Pages hosts static sites and SPAs. For a Vite + React app:

```bash
# Create a Pages project
wrangler pages project create my-app
```

## Build with Environment Variables

Vite exposes variables prefixed with `VITE_` to client code. Set them at build time for each environment.

```bash
# Staging build
VITE_API_URL="https://staging-api.example.com" \
VITE_ENABLE_TEST_ROUTES="true" \
  npm run build

# Production build
VITE_API_URL="https://api.example.com" \
VITE_ENABLE_TEST_ROUTES="false" \
  npm run build
```

Access in code:

```typescript
const API_URL = import.meta.env.VITE_API_URL;
```

## Deploy to Pages

```bash
# Deploy to production (main branch)
wrangler pages deploy dist \
  --project-name=my-app \
  --branch=main

# Deploy to staging (preview)
wrangler pages deploy dist \
  --project-name=my-app \
  --branch=staging
```

Branch-based deploys create preview URLs:
- `main` branch: `my-app.pages.dev` (and custom domain if configured)
- `staging` branch: `staging.my-app.pages.dev`

## Custom Domains

Configure in the Cloudflare dashboard:
1. Go to Pages project settings
2. Add custom domain: `app.example.com`
3. DNS is auto-configured if the zone is on Cloudflare

## SPA Routing

For client-side routing (React Router, etc.), Pages needs to serve `index.html` for all paths. Create a `_redirects` file in the build output:

```
/*  /index.html  200
```

Or use `_headers` for cache control:

```
/*
  Cache-Control: no-cache

/assets/*
  Cache-Control: public, max-age=31536000, immutable
```

## Integration with Worker API

The Pages frontend calls the Worker API. Set the API URL via environment variable:

```typescript
// src/config.ts
export const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8787";
```

For local development, the Vite dev server proxies to the local worker to avoid CORS issues:

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

## Deploy Script Integration

Include Pages deployment as the final step in your deploy script:

```bash
deploy_frontend() {
  local branch="$1"  # "main" or "staging"
  local api_url="$2"

  cd apps/web
  VITE_API_URL="$api_url" npm run build
  wrangler pages deploy dist \
    --project-name=my-app \
    --branch="$branch"
  cd ../..
}
```
