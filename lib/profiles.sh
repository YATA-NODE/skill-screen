#!/usr/bin/env bash
# profiles.sh — structure profiles for the kinds of skill/extension layouts we screen.
#
# A profile does NOT decide which files get scanned (scan.sh always scans every
# non-denylisted file — "scan superset" is a safety invariant). A profile only
# lets us auto-detect what kind of thing we're looking at, for context in the
# output. File roles (instruction vs executable vs other) are derived purely from
# the path/extension and are independent of the profile.
#
# Source-only.
#
# Supported profiles (they only drive auto-detection — they never change WHICH
# files are scanned, nor how files are labelled; "scan superset" is a safety
# invariant):
#   agent-skill  : an agent skill — has SKILL.md at the top level. SKILL.md is the
#                  open agent skills spec used by BOTH Claude Code and OpenAI Codex,
#                  so the same profile covers a skill from either tool.
#   generic      : anything else — scan everything, classify by extension only.
#
# We deliberately do NOT special-case any tool's own instruction filename
# (AGENTS.md for Codex, CLAUDE.md for Claude Code, etc.). Every file is scanned
# regardless, and instruction-like files (*.md / *.txt) are labelled "instruction"
# by extension alone, so no single tool is privileged and none is omitted.

# profiles::detect <dir> -> prints one of: agent-skill | generic
profiles::detect() {
  local dir="$1"
  [ -d "$dir" ] || { echo "generic"; return 0; }
  # SKILL.md = the open agent skills spec, shared by Claude Code and OpenAI Codex.
  if [ -f "$dir/SKILL.md" ]; then
    echo "agent-skill"; return 0
  fi
  echo "generic"
}

# profiles::role <relpath> -> prints: instruction | executable | other
# Classification is by path/extension only; it is advisory context, profile-independent.
# Instruction-like files (any *.md / *.txt) are labelled "instruction" — this covers
# SKILL.md, AGENTS.md, CLAUDE.md and any other prose an agent might read, symmetrically.
profiles::role() {
  local rel="$1"
  case "$rel" in
    *.sh|*.bash|*.zsh|*.fish|*.js|*.mjs|*.cjs|*.ts|*.py|*.rb|*.pl|*.php)
      echo "executable"; return 0 ;;
    *.md|*.txt)
      echo "instruction"; return 0 ;;
  esac
  echo "other"
}
