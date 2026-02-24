# Cloudflare Basic Infra Starter Skill

An [Agent Skill](https://agentskills.io/specification) packaging proven infrastructure patterns for small projects on Cloudflare Workers + D1 + Pages. When installed, your coding agent already knows how to structure workers, design D1 schemas, configure multi-environment Wrangler, write safe deploy scripts, and set up testing.

Extracted from a production Cloudflare project. All patterns are generalized -- no project-specific references.

## What's Covered

| Reference | Patterns |
|-----------|----------|
| [Worker Architecture](references/worker-architecture.md) | Typed Env interface, fetch handler structure, request routing, response finalization, `ctx.waitUntil()` |
| [D1 Database](references/d1-database.md) | hex randomblob IDs, ISO timestamps, soft delete, atomic counters, migration naming, why CHECK constraints are forbidden |
| [Wrangler Environments](references/wrangler-environments.md) | Multi-env wrangler.toml (local/staging/prod), per-env bindings, secrets management, route patterns |
| [Deployment Scripts](references/deployment-scripts.md) | Migration safety scan, retry with backoff, idempotency via health SHA, version tagging, deploy logging |
| [Testing Workers](references/testing-workers.md) | Local dev with Miniflare, test endpoint gating, `@cloudflare/vitest-pool-workers`, E2E setup |
| [Pages Frontend](references/pages-frontend.md) | Vite SPA build, `VITE_*` env vars, branch-based deploys, SPA routing, Vite proxy for local dev |
| [Auth and Security](references/auth-and-security.md) | API key hash auth, session cookie fallback, security headers, CORS, request validation |
| [Local Development](references/local-development.md) | Zero-to-running walkthrough, Miniflare local SQLite, Vite proxy, database reset, test setup |
| [Health and Ops](references/health-and-ops.md) | Health endpoint, version injection, deployment CSV log, environment status checks, observability config |

Starter templates in [`assets/`](assets/): a `wrangler.toml.template` and `deploy.sh.template` ready to copy and customize.

## Install

### Claude Code plugin (auto-updates)

Install as a plugin for automatic updates when the skill changes:

```
/plugin marketplace add boxabirds/cloudflare-basic-infra-starter-skill
/plugin install cloudflare-basic-infra-starter@cloudflare-basic-infra-starter-skill
```

### File-based install (all agents)

Most agents scan `.agents/skills/` — clone there for the broadest coverage:

```bash
git clone git@github.com:boxabirds/cloudflare-basic-infra-starter-skill.git \
  .agents/skills/cloudflare-basic-infra-starter
```

### Agent-specific paths

| Agent | Skills path | Notes |
|-------|-------------|-------|
| Codex, Amp, Cline, Roo Code | `.agents/skills/cloudflare-basic-infra-starter` | Universal path |
| Cursor | `.cursor/skills/cloudflare-basic-infra-starter` | Also scans `.agents/skills/` |
| GitHub Copilot | `.github/skills/cloudflare-basic-infra-starter` | Also scans `.agents/skills/` |
| Claude Code | `.claude/skills/cloudflare-basic-infra-starter` | Requires its own path |
| Windsurf | `.windsurf/skills/cloudflare-basic-infra-starter` | Requires its own path |
| Gemini CLI | `.gemini/skills/cloudflare-basic-infra-starter` | Also scans `.agents/skills/` |

### Install script (multi-agent symlink)

Symlinks the skill into one or more agent paths at once:

```bash
./scripts/install.sh /path/to/your/project                        # auto-detect agents
./scripts/install.sh /path/to/your/project claude                  # specific agent
./scripts/install.sh /path/to/your/project claude amp windsurf     # multiple
```

Supported agents: `claude`, `amp`, `copilot`, `cursor`, `codex`, `windsurf`, `gemini`, `cline`, `roo`.

### Registries

The skill can also be discovered through these directories:

- **[skills.sh](https://skills.sh)** — `npx skills add boxabirds/cloudflare-basic-infra-starter-skill`
- **[skild.sh](https://skild.sh)** — `skild install boxabirds/cloudflare-basic-infra-starter-skill`

## After Installation

The skill appears in Claude Code's `/` menu as **`/cloudflare-basic-infra-starter`**.

**Explicit invocation**: Type `/cloudflare-basic-infra-starter` to load all Cloudflare patterns into context.

**Auto-activation**: Claude will attempt to load the skill automatically when you discuss Cloudflare Workers, D1, Wrangler, or Pages. Auto-activation is not 100% reliable -- if Claude doesn't pick it up, type `/cloudflare-basic-infra-starter` explicitly.

**Verify installation**: Ask Claude "What skills are available?" or check the `/` menu.

Example prompts that should trigger the skill:
- "Set up a new Cloudflare Worker with D1"
- "Create a deployment script for my worker"
- "How should I structure my wrangler.toml for staging and prod?"
- "Add a D1 database with soft delete to my worker"
- "Help me get local dev running with Miniflare"

## How It Works

The skill uses the [Agent Skills](https://agentskills.io/specification) progressive disclosure model:

1. **At startup**: The agent reads `name` and `description` from SKILL.md frontmatter (~100 tokens) to know the skill exists
2. **On activation**: When the task involves Cloudflare Workers, the agent loads the full SKILL.md body (~1100 tokens) with pattern summaries
3. **On demand**: The agent reads individual `references/*.md` files only when it needs the detailed patterns and code examples

This keeps context usage minimal until the knowledge is actually needed.

## License

Apache-2.0
