# Worker Architecture

## Env Interface

Declare all Cloudflare bindings in a typed interface. Mark optional bindings so the worker degrades gracefully when bindings aren't configured (e.g., local dev without KV).

```typescript
export interface Env {
  // Required
  DB: D1Database;

  // Optional -- worker functions without these, just with reduced capabilities
  SESSION_KV?: KVNamespace;
  ANALYTICS?: AnalyticsEngineDataset;

  // Secrets -- set via `wrangler secret put`, never in [vars]
  GITHUB_APP_CLIENT_ID?: string;
  GITHUB_APP_CLIENT_SECRET?: string;

  // Environment metadata
  ENVIRONMENT?: string;  // "local", "staging", "production"
  BASE_URL?: string;     // e.g., "https://api.example.com"
}
```

## Fetch Handler Entry Point

The worker exports a single `fetch` handler. Keep it thin -- delegate to a `handleRequest` function.

```typescript
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, ctx);
  },
};
```

## Request Handler Structure

A single function with a clear flow: validate, route, authenticate, dispatch, finalize.

```typescript
export async function handleRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  const url = new URL(request.url);
  const requestId = crypto.randomUUID();
  const corsHeaders = getCorsHeaders(env);

  try {
    // 1. Validate request (method, content-type, body size)
    const validation = validateRequest(request);
    if (!validation.valid) {
      return finalizeResponse(
        errorResponse(validation.error!, validation.statusCode!, corsHeaders),
        requestId
      );
    }

    // 2. Health check (no auth required)
    if (url.pathname === "/health") {
      return finalizeResponse(healthResponse(env), requestId);
    }

    // 3. No-auth routes (OAuth callbacks, setup flows)
    if (isNoAuthPath(url.pathname)) {
      return finalizeResponse(
        await handleNoAuthRoute(request, env),
        requestId
      );
    }

    // 4. Test endpoints (disabled in production)
    if (url.pathname.startsWith("/test/")) {
      if (env.ENVIRONMENT === "production") {
        return finalizeResponse(notFoundResponse(), requestId);
      }
      return finalizeResponse(
        await handleTestRoute(request, env),
        requestId
      );
    }

    // 5. Authenticate
    const auth = await authenticate(request, env);
    if (!auth.user) {
      return finalizeResponse(unauthorizedResponse(corsHeaders), requestId);
    }

    // 6. Dispatch to route handler
    const response = await dispatch(request, env, auth);
    return finalizeResponse(response, requestId);

  } catch (error) {
    console.error("Unhandled error:", error);
    return finalizeResponse(
      errorResponse("Internal server error", 500, corsHeaders),
      requestId
    );
  } finally {
    // Async cleanup -- doesn't block response
    ctx.waitUntil(flushAnalytics());
  }
}
```

## Response Finalization

Every response passes through `finalizeResponse` to get security headers and a request ID. This guarantees consistent headers regardless of which code path generated the response.

```typescript
function finalizeResponse(response: Response, requestId: string): Response {
  const headers = new Headers(response.headers);

  // Security headers
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Frame-Options", "DENY");
  headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  headers.set("Content-Security-Policy", "frame-ancestors 'none'");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");

  // Request tracing
  headers.set("X-Request-Id", requestId);

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
```

## Anti-Patterns

- **Don't use a framework for simple workers.** A bare `fetch` handler with URL path matching is cleaner and has zero dependencies for workers with <20 routes. Frameworks (Hono, itty-router) are justified for larger workers with middleware chains.
- **Don't hardcode CORS origins.** Read from `env.WEB_APP_URL` and fall back to `http://localhost:*` for local dev.
- **Don't forget `ctx.waitUntil()`.** Without it, async operations after `return` may be killed before completing.
