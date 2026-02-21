#!/bin/bash
# Install this skill into a project for one or more coding agents.
#
# Usage:
#   ./scripts/install.sh /path/to/project [agent...]
#
# Examples:
#   ./scripts/install.sh ~/my-project                  # Auto-detect agents
#   ./scripts/install.sh ~/my-project claude            # Claude Code only
#   ./scripts/install.sh ~/my-project claude amp cursor # Multiple agents
#
# Supported agents: claude, amp, copilot, cursor, codex
# For Windsurf/Cline (no skills support), see README.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_NAME="cf-starter"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-path> [agent...]"
  echo ""
  echo "Agents: claude, amp, copilot, cursor, codex"
  echo "If no agents specified, auto-detects from project directory."
  exit 1
fi

PROJECT_DIR="$1"
shift

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: $PROJECT_DIR is not a directory."
  exit 1
fi

# Agent -> skills directory mapping
declare -A AGENT_PATHS
AGENT_PATHS[claude]=".claude/skills"
AGENT_PATHS[amp]=".agents/skills"
AGENT_PATHS[copilot]=".github/skills"
AGENT_PATHS[cursor]=".cursor/skills"
AGENT_PATHS[codex]="skills"

# Auto-detect agents if none specified
AGENTS=("$@")
if [ ${#AGENTS[@]} -eq 0 ]; then
  for agent in "${!AGENT_PATHS[@]}"; do
    parent_dir=$(dirname "${AGENT_PATHS[$agent]}")
    if [ -d "$PROJECT_DIR/$parent_dir" ]; then
      AGENTS+=("$agent")
    fi
  done

  # Default to Claude Code if nothing detected
  if [ ${#AGENTS[@]} -eq 0 ]; then
    AGENTS=("claude")
  fi
fi

# Install for each agent
for agent in "${AGENTS[@]}"; do
  if [ -z "${AGENT_PATHS[$agent]+x}" ]; then
    echo "WARNING: Unknown agent '$agent'. Skipping."
    continue
  fi

  TARGET_DIR="$PROJECT_DIR/${AGENT_PATHS[$agent]}/$SKILL_NAME"

  if [ -d "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    echo "SKIP: $agent -- already installed at ${AGENT_PATHS[$agent]}/$SKILL_NAME"
    continue
  fi

  mkdir -p "$(dirname "$TARGET_DIR")"

  # Symlink to the skill directory
  ln -s "$SKILL_DIR" "$TARGET_DIR"
  echo "OK: $agent -- symlinked to ${AGENT_PATHS[$agent]}/$SKILL_NAME"
done

echo ""
echo "Done. Restart your coding agent to pick up the skill."
echo ""
echo "In Claude Code, type /cf-starter to load Cloudflare patterns."
echo "Or just mention Cloudflare Workers/D1/Wrangler -- Claude will auto-activate."
