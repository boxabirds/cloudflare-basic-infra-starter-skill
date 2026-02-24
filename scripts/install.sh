#!/usr/bin/env bash
# Install this skill into a project for one or more coding agents.
#
# Usage:
#   ./scripts/install.sh /path/to/project [agent...]
#
# Examples:
#   ./scripts/install.sh ~/my-project                        # Auto-detect agents
#   ./scripts/install.sh ~/my-project claude                  # Claude Code only
#   ./scripts/install.sh ~/my-project claude amp cursor       # Multiple agents
#
# Supported agents: claude, amp, copilot, cursor, codex, windsurf, gemini, cline, roo
# Most agents scan .agents/skills/ -- Claude Code and Windsurf need their own paths.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_NAME="cf-starter"
ALL_AGENTS="claude amp copilot cursor codex windsurf gemini cline roo"

# Agent -> skills directory mapping
# .agents/skills/ is the universal path (Codex, Amp, Cline, Roo, Gemini alias, Cursor, Copilot)
# Claude Code and Windsurf require their own paths
skills_path_for() {
  case "$1" in
    claude)   echo ".claude/skills" ;;
    cursor)   echo ".cursor/skills" ;;
    copilot)  echo ".github/skills" ;;
    windsurf) echo ".windsurf/skills" ;;
    gemini)   echo ".gemini/skills" ;;
    amp|codex|cline|roo) echo ".agents/skills" ;;
    *)        return 1 ;;
  esac
}

# Directory to check during auto-detect
detect_dir_for() {
  case "$1" in
    claude)   echo ".claude" ;;
    cursor)   echo ".cursor" ;;
    copilot)  echo ".github" ;;
    windsurf) echo ".windsurf" ;;
    gemini)   echo ".gemini" ;;
    roo)      echo ".roo" ;;
    amp|codex|cline) echo ".agents" ;;
    *)        return 1 ;;
  esac
}

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-path> [agent...]"
  echo ""
  echo "Agents: $ALL_AGENTS"
  echo "If no agents specified, auto-detects from project directory."
  exit 1
fi

PROJECT_DIR="$1"
shift

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: $PROJECT_DIR is not a directory."
  exit 1
fi

# Collect agents
AGENTS=""
if [ $# -gt 0 ]; then
  AGENTS="$*"
else
  # Auto-detect from existing directories
  for agent in $ALL_AGENTS; do
    dir=$(detect_dir_for "$agent")
    if [ -d "$PROJECT_DIR/$dir" ]; then
      AGENTS="$AGENTS $agent"
    fi
  done

  # Default to .agents/skills/ (broadest coverage) if nothing detected
  if [ -z "$AGENTS" ]; then
    AGENTS="codex"
    echo "No agent directories detected. Defaulting to .agents/skills/ (universal path)."
  fi
fi

# Track installed paths to avoid duplicate symlinks (space-delimited list)
INSTALLED_PATHS=""
INSTALLED_COUNT=0

for agent in $AGENTS; do
  skills_path=$(skills_path_for "$agent" 2>/dev/null) || {
    echo "WARNING: Unknown agent '$agent'. Skipping."
    continue
  }

  TARGET_DIR="$PROJECT_DIR/$skills_path/$SKILL_NAME"

  # Skip if we already created a symlink at this path (multiple agents share .agents/skills/)
  case " $INSTALLED_PATHS " in
    *" $skills_path "*) continue ;;
  esac

  if [ -d "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    echo "SKIP: $agent -- already installed at $skills_path/$SKILL_NAME"
    INSTALLED_PATHS="$INSTALLED_PATHS $skills_path"
    continue
  fi

  mkdir -p "$(dirname "$TARGET_DIR")"

  ln -s "$SKILL_DIR" "$TARGET_DIR"
  echo "  OK: $agent -- symlinked to $skills_path/$SKILL_NAME"
  INSTALLED_PATHS="$INSTALLED_PATHS $skills_path"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done

echo ""
if [ "$INSTALLED_COUNT" -gt 0 ]; then
  echo "Done. Restart your coding agent to pick up the skill."
else
  echo "No new installations needed."
fi
