# D1 Database Patterns

## Schema Conventions

### Primary Keys

Use 16-byte random hex strings, not autoincrement integers. This avoids sequential ID guessing and works across distributed systems.

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
  email TEXT UNIQUE NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);
```

### Timestamps

Always use ISO 8601 UTC strings via `datetime('now')`. D1/SQLite has no native datetime type -- TEXT columns with ISO strings sort correctly and are human-readable.

```sql
created_at TEXT DEFAULT (datetime('now')),
updated_at TEXT DEFAULT (datetime('now'))
```

### Soft Delete

Add two columns to every table that needs deletion:

```sql
deleted INTEGER DEFAULT 0,    -- 0 = visible, 1 = soft deleted
deleted_at TEXT               -- ISO timestamp of deletion
```

Every query filters with `AND deleted = 0`. Restore by setting `deleted = 0` and clearing `deleted_at`.

### Foreign Keys

Use TEXT references matching the hex ID format. Always index FK columns.

```sql
CREATE TABLE posts (
  id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
  project_id TEXT NOT NULL REFERENCES projects(id),
  author_id TEXT REFERENCES users(id),
  -- ...
);

CREATE INDEX idx_posts_project ON posts(project_id);
CREATE INDEX idx_posts_author ON posts(author_id);
```

### JSON Columns

Store structured data as TEXT columns containing JSON. D1 supports `json_extract()` for querying.

```sql
settings TEXT,           -- JSON: {"theme": "dark", "notifications": true}
tags TEXT,               -- JSON array: ["typescript", "cloudflare"]
```

### User-Facing IDs

Don't expose hex IDs to users. Use an atomic counter table:

```sql
CREATE TABLE counters (
  id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
  project_id TEXT NOT NULL REFERENCES projects(id),
  name TEXT NOT NULL,        -- e.g., "story_counter"
  value INTEGER DEFAULT 0,
  UNIQUE(project_id, name)
);
```

Increment atomically:

```typescript
const result = await env.DB.prepare(
  "UPDATE counters SET value = value + 1 WHERE project_id = ? AND name = ? RETURNING value"
).bind(projectId, counterName).first<{ value: number }>();

const nextId = result!.value; // e.g., 42
```

## Migration Patterns

### Naming Convention

```
migrations/
├── 0001_initial_schema.sql
├── 0002_add_user_roles.sql
├── 0003_add_soft_delete_to_posts.sql
└── 0004_add_analytics_tables.sql
```

Sequential four-digit prefix, snake_case description. Wrangler auto-applies pending migrations in order.

### Apply Migrations

```bash
# Local
wrangler d1 migrations apply DB --local

# Staging
wrangler d1 migrations apply DB --env staging --remote

# Production
wrangler d1 migrations apply DB --env production --remote
```

### Adding Columns (Safe)

```sql
ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'member';
ALTER TABLE users ADD COLUMN avatar_url TEXT;
```

### Adding Soft Delete to Existing Table

```sql
ALTER TABLE posts ADD COLUMN deleted INTEGER DEFAULT 0;
ALTER TABLE posts ADD COLUMN deleted_at TEXT;
CREATE INDEX idx_posts_deleted ON posts(deleted);
```

## Critical Anti-Patterns

### Never Use CHECK Constraints

CHECK constraints in SQLite/D1 are **immutable after creation**. You cannot ALTER, DROP, or modify them. The only way to remove a CHECK constraint is to recreate the entire table:

1. Create a new table without the constraint
2. Copy all data
3. Drop the original table
4. Rename the new table

This is error-prone and can fail catastrophically with foreign key references. **Always validate enums and ranges in application code instead.**

```sql
-- BAD: Cannot be changed later
status TEXT NOT NULL CHECK (status IN ('active', 'inactive'))

-- GOOD: Validate in application code
status TEXT NOT NULL DEFAULT 'active'  -- App validates: active, inactive
```

### Never DROP TABLE in Migrations (Except Temp Tables)

Dropping tables loses data. Use soft delete columns instead. The only exception is temporary tables used during migration (named `*_new`, `*_old`, `*_temp`, `*_backup`).

### No ALTER TABLE MODIFY/CHANGE

SQLite doesn't support `ALTER TABLE ... MODIFY COLUMN` or `ALTER TABLE ... CHANGE COLUMN`. The only supported ALTER TABLE operations are:

- `ADD COLUMN`
- `DROP COLUMN` (SQLite 3.35+)
- `RENAME COLUMN` (SQLite 3.25+)
- `RENAME TO`

## Migration Safety Checks

Before deploying, scan pending migrations for dangerous patterns:

```bash
DANGEROUS_PATTERNS=(
  "CHECK ("
  "DROP TABLE"
  "TRUNCATE TABLE"
  "ALTER TABLE.*MODIFY"
  "ALTER TABLE.*CHANGE"
  "ADD CONSTRAINT"
  "DROP CONSTRAINT"
)

for migration in migrations/*.sql; do
  for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if grep -qiE "$pattern" "$migration"; then
      echo "DANGEROUS: $migration contains '$pattern'"
      exit 1
    fi
  done
done
```
