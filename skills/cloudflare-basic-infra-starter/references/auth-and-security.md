# Auth and Security

## Authentication Middleware Pattern

Check API key first, then session cookie, then reject. Declare no-auth paths upfront.

```typescript
interface AuthResult {
  user: { id: string } | null;
  method: "api_key" | "session" | null;
}

async function authenticate(request: Request, env: Env): Promise<AuthResult> {
  // 1. Try API key (X-Api-Key header)
  const apiKey = request.headers.get("x-api-key");
  if (apiKey) {
    return authenticateApiKey(apiKey, env);
  }

  // 2. Try session cookie
  const cookieHeader = request.headers.get("Cookie");
  if (cookieHeader && env.SESSION_KV) {
    return authenticateSession(cookieHeader, env);
  }

  // 3. Neither present
  return { user: null, method: null };
}
```

### API Key Authentication

Hash the provided key with SHA-256 and look up the hash in the database. Never store raw API keys.

```typescript
async function authenticateApiKey(apiKey: string, env: Env): Promise<AuthResult> {
  const keyHash = await sha256(apiKey);

  const record = await env.DB.prepare(
    "SELECT user_id FROM api_keys WHERE key_hash = ?"
  ).bind(keyHash).first<{ user_id: string | null }>();

  if (!record || !record.user_id) {
    return { user: null, method: null };
  }

  // Verify the user still exists
  const user = await env.DB.prepare(
    "SELECT id FROM users WHERE id = ?"
  ).bind(record.user_id).first<{ id: string }>();

  if (!user) {
    return { user: null, method: null };
  }

  return { user, method: "api_key" };
}

async function sha256(message: string): Promise<string> {
  const data = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}
```

### Session Cookie Authentication

Store sessions in KV with a TTL. Extract session ID from the cookie header.

```typescript
async function authenticateSession(
  cookieHeader: string,
  env: Env
): Promise<AuthResult> {
  const sessionId = extractSessionId(cookieHeader);
  if (!sessionId) {
    return { user: null, method: null };
  }

  const session = await env.SESSION_KV!.get(sessionId, "json") as
    { userId: string; expiresAt: string } | null;

  if (!session || new Date(session.expiresAt) < new Date()) {
    return { user: null, method: null };
  }

  return { user: { id: session.userId }, method: "session" };
}
```

## No-Auth Path Declaration

Declare which paths bypass authentication upfront, before the auth check runs.

```typescript
const NO_AUTH_PREFIXES = [
  "/health",
  "/auth/callback",
  "/auth/login",
  "/setup/",
];

function isNoAuthPath(pathname: string): boolean {
  return NO_AUTH_PREFIXES.some(prefix => pathname.startsWith(prefix));
}
```

## Security Headers

Apply to every response via the finalization pattern:

```typescript
const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",       // Prevent MIME sniffing
  "X-Frame-Options": "DENY",                  // Prevent clickjacking
  "X-XSS-Protection": "1; mode=block",       // Legacy XSS protection
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Cache-Control": "no-store, no-cache, must-revalidate",
  "Pragma": "no-cache",
  "Content-Security-Policy": "frame-ancestors 'none'",
};
```

## Request Validation

Validate before routing to catch malformed requests early:

```typescript
const MAX_BODY_SIZE_BYTES = 1024 * 1024; // 1MB

function validateRequest(request: Request): { valid: boolean; error?: string; statusCode?: number } {
  // 1. HTTP method
  const ALLOWED_METHODS = ["GET", "POST", "PATCH", "DELETE"];
  if (!ALLOWED_METHODS.includes(request.method)) {
    return { valid: false, error: "Method not allowed", statusCode: 405 };
  }

  // 2. Content-Type for POST
  if (request.method === "POST") {
    const contentType = request.headers.get("content-type");
    if (!contentType?.includes("application/json")) {
      return { valid: false, error: "Content-Type must be application/json", statusCode: 415 };
    }
  }

  // 3. Body size
  const contentLength = request.headers.get("content-length");
  if (contentLength) {
    const size = parseInt(contentLength, 10);
    if (!isNaN(size) && size > MAX_BODY_SIZE_BYTES) {
      return { valid: false, error: "Request body too large", statusCode: 413 };
    }
  }

  return { valid: true };
}
```

## CORS

Compute the allowed origin from an environment variable. Never hardcode origins.

```typescript
function getCorsHeaders(env: Env): Record<string, string> {
  const allowedOrigin = env.WEB_APP_URL || "http://localhost:5173";

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Api-Key, Authorization",
    "Access-Control-Allow-Credentials": "true",
    "Access-Control-Max-Age": "86400",
  };
}
```

Handle preflight:

```typescript
if (request.method === "OPTIONS") {
  return new Response(null, { status: 204, headers: corsHeaders });
}
```
