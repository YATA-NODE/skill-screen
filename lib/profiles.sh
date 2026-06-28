#!/usr/bin/env bash
# profiles.sh — structure profiles for the kinds of skill/extension layouts we screen.
#
# A profile does NOT decide which files get scanned (scan.sh always scans every
# non-denylisted file — "scan superset" is a safety invariant). A profile only:
#   1. lets us auto-detect what kind of thing we're looking at, and
#   2. labels each file's role (instruction vs executable vs other) for context in
#      the output and the stage-2 prompt.
#
# Source-only.
#
# Supported profiles:
#   claude-code-skill : a Claude Code skill (has SKILL.md at the top level)
#   codex-extension   : a Codex CLI extension/prompt (AGENTS.md or config.toml, no SKILL.md)
#   generic           : anything else — scan everything, classify by extension only
#
# The codex-extension layout is detected loosely on purpose; until its spec is
# pinned down we fall back to generic behavior (scan all, conservative), which is
# the safe side.

# profiles::detect <dir> -> prints one of: claude-code-skill | codex-extension | generic
profiles::detect() {
  local dir="$1"
  [ -d "$dir" ] || { echo "generic"; return 0; }
  if [ -f "$dir/SKILL.md" ]; then
    echo "claude-code-skill"; return 0
  fi
  if [ -f "$dir/AGENTS.md" ] || [ -f "$dir/config.toml" ] || [ -f "$dir/.codex/config.toml" ]; then
    echo "codex-extension"; return 0
  fi
  echo "generic"
}

# profiles::role <relpath> <profile> -> prints: instruction | executable | other
# Classification is by path/extension; it is advisory context only.
profiles::role() {
  local rel="$1" profile="$2"
  local base; base="$(basename -- "$rel")"
  case "$rel" in
    *.sh|*.bash|*.zsh|*.fish|*.js|*.mjs|*.cjs|*.ts|*.py|*.rb|*.pl|*.php)
      echo "executable"; return 0 ;;
  esac
  case "$profile" in
    claude-code-skill)
      case "$base" in
        SKILL.md) echo "instruction"; return 0 ;;
      esac
      case "$rel" in
        *.md|*.txt) echo "instruction"; return 0 ;;
      esac ;;
    codex-extension)
      case "$base" in
        AGENTS.md|config.toml) echo "instruction"; return 0 ;;
      esac
      case "$rel" in
        *.md|*.toml|*.txt) echo "instruction"; return 0 ;;
      esac ;;
    *)
      case "$rel" in
        *.md|*.txt) echo "instruction"; return 0 ;;
      esac ;;
  esac
  echo "other"
}
