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
# Supported profiles (they only label files and drive auto-detection — they never
# change WHICH files are scanned; "scan superset" is a safety invariant):
#   agent-skill  : an agent skill — has SKILL.md at the top level. SKILL.md is the
#                  open agent skills spec used by BOTH Claude Code and OpenAI Codex,
#                  so the same profile covers a skill from either tool.
#   codex-config : Codex custom instructions / config — AGENTS.md, AGENTS.override.md,
#                  config.toml, or .codex/config.toml, and no SKILL.md. AGENTS.md is a
#                  custom *instructions* file, NOT a skill (see OpenAI Codex docs), but
#                  an agent reads it, so it is still worth screening.
#   generic      : anything else — scan everything, classify by extension only.
#
# codex-config is detected loosely on purpose; we scan everything regardless, so an
# imperfect label never narrows the scan (the safe side).

# profiles::detect <dir> -> prints one of: agent-skill | codex-config | generic
profiles::detect() {
  local dir="$1"
  [ -d "$dir" ] || { echo "generic"; return 0; }
  # SKILL.md = the open agent skills spec, shared by Claude Code and OpenAI Codex.
  if [ -f "$dir/SKILL.md" ]; then
    echo "agent-skill"; return 0
  fi
  # AGENTS.md / AGENTS.override.md = Codex custom instructions; config.toml /
  # .codex/config.toml = Codex config. None is a skill, but worth screening.
  if [ -f "$dir/AGENTS.md" ] || [ -f "$dir/AGENTS.override.md" ] \
     || [ -f "$dir/config.toml" ] || [ -f "$dir/.codex/config.toml" ]; then
    echo "codex-config"; return 0
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
    agent-skill)
      case "$base" in
        SKILL.md) echo "instruction"; return 0 ;;
      esac
      case "$rel" in
        *.md|*.txt) echo "instruction"; return 0 ;;
      esac ;;
    codex-config)
      case "$base" in
        AGENTS.md|AGENTS.override.md|config.toml) echo "instruction"; return 0 ;;
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
