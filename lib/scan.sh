#!/usr/bin/env bash
# scan.sh — stage-1 mechanical scanner: walk a skill dir, grep the ruleset, emit JSON.
#
# Source-only. Depends on patterns.sh and profiles.sh being sourced first.
# External tools: grep, sha256sum, timeout (coreutils), and jq for clean JSON
# (degrades to a minimal JSON if jq is absent).
#
# Safety invariants:
#   - "scan superset": every non-denylisted file is scanned. We never narrow the
#     scan based on profile/extension — that would let a payload hide in an
#     unexpected file type.
#   - fail-closed: a timeout or a control-char filename produces a blocked signal,
#     never a silent "clean".
#   - no raw secrets escape: secret matches are masked before they enter output.

SKC_MATCH_CAP="${SKC_MATCH_CAP:-20}"        # max matches recorded per file+pattern
SKC_GREP_TIMEOUT="${SKC_GREP_TIMEOUT:-15}"  # seconds per grep invocation
SKC_EXCERPT_MAX="${SKC_EXCERPT_MAX:-200}"   # max chars of a matched line kept

# Directories/files never scanned or hashed (noise + secrets, defense in depth).
_skc_is_denied() {
  case "$1" in
    .git/*|*/.git/*|.git) return 0 ;;
    node_modules/*|*/node_modules/*) return 0 ;;
    .venv/*|*/.venv/*|__pycache__/*|*/__pycache__/*) return 0 ;;
    *.pyc) return 0 ;;
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
  esac
  return 1
}

# scan::list_files <dir> -> relative paths (one per line), denylist applied.
# Runs in a subshell when used in $(...) / <(...), so it cannot set a parent global.
# Instead, if SKC_BADNAME_FLAG points to a file, it appends a byte there whenever a
# path with a control char (or embedded newline) is seen — an evasion red flag the
# caller checks after the scan.
scan::list_files() {
  local dir="$1" rel real base
  # Include symlinks (-type l): a skill whose SKILL.md is a symlink pointing OUTSIDE
  # the target would otherwise be detected (profiles::detect follows the link) yet
  # never scanned (find -type f skips links) = an evaluation bypass. We resolve each
  # symlink: if it stays inside the target and is a regular file, scan it; if it
  # escapes the target (or can't be resolved), flag it (red flag) and never read it
  # (no path traversal out of the target).
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    [ -z "$rel" ] && continue
    _skc_is_denied "$rel" && continue
    case "$rel" in
      *[$'\001'-$'\037']*)
        [ -n "${SKC_BADNAME_FLAG:-}" ] && printf 1 >> "$SKC_BADNAME_FLAG"
        continue ;;
    esac
    if [ -L "$dir/$rel" ]; then
      real="" ; base=""
      if command -v realpath >/dev/null 2>&1; then
        real="$(realpath -m -- "$dir/$rel" 2>/dev/null)"
        base="$(realpath -m -- "$dir" 2>/dev/null)"
      fi
      if [ -n "$real" ] && { [ "$real" = "$base" ] || case "$real" in "$base"/*) true ;; *) false ;; esac; }; then
        [ -f "$dir/$rel" ] && printf '%s\n' "$rel"   # in-tree regular file: scan it
      else
        [ -n "${SKC_BADNAME_FLAG:-}" ] && printf 1 >> "$SKC_BADNAME_FLAG"  # escapes target
      fi
      continue
    fi
    printf '%s\n' "$rel"
  done < <(cd "$dir" 2>/dev/null && find . \( -type f -o -type l \) -print0 2>/dev/null)
}

# scan::content_hash <dir> -> "sha256:<hex>" over (relpath + US + sha256(content)),
# sorted for determinism. Mirrors the internal audit-hash approach.
scan::content_hash() {
  local dir="$1" rel sum
  command -v sha256sum >/dev/null 2>&1 || { echo "sha256:unavailable"; return 0; }
  sum="$(scan::list_files "$dir" | LC_ALL=C sort | while IFS= read -r rel; do
    printf '%s\037%s\n' "$rel" "$(sha256sum "$dir/$rel" 2>/dev/null | cut -d' ' -f1)"
  done | sha256sum | cut -d' ' -f1)"
  echo "sha256:$sum"
}

# _skc_redact <string> -> mask any secret-pattern match (upholds the masking
# invariant for the hits excerpt channel, not just secret_hits). A secret can ride
# on a line that matches a warning pattern (e.g. an Authorization header on a
# net-call line); without this, the raw token would land verbatim in hits[].excerpt.
_skc_redact() {
  local s="$1" entry regex
  if declare -F patterns::secret_patterns >/dev/null 2>&1; then
    while IFS= read -r entry; do
      regex="${entry##*|}"
      [ -z "$regex" ] && continue
      s="$(printf '%s' "$s" | sed -E "s/${regex}/[REDACTED-SECRET]/g" 2>/dev/null || printf '%s' "$s")"
    done < <(patterns::secret_patterns)
  fi
  printf '%s' "$s"
}

# _skc_sanitize <string> -> printable, delimiter-free, secret-masked, truncated.
# Truncation uses bash substring (character-based under a UTF-8 locale) to avoid
# cutting a multibyte character in half, which could yield invalid UTF-8 and break
# the downstream `jq -R`.
_skc_sanitize() {
  local s
  s="$(printf '%s' "$1" | tr -d '\000-\037')"
  s="$(_skc_redact "$s")"
  printf '%s' "${s:0:$SKC_EXCERPT_MAX}"
}

# _skc_has_placeholder <line> -> 0 if the line looks like docs/example (skip secret hit)
_skc_has_placeholder() {
  printf '%s' "$1" | grep -qiE 'EXAMPLE|DUMMY|TEST|SAMPLE|PLACEHOLDER|YOUR_|<your-|xxxxx'
}

# _skc_mask <token> -> first 4 chars + "***" (raw secret never leaves the function)
_skc_mask() {
  printf '%s***' "$(printf '%s' "$1" | cut -c1-4)"
}

# _skc_emit_json <dir> <profile> <content_hash> <files> <patterns> <signal>
#                <hits_tmp> <secret_tmp>  -> JSON on stdout.
# Uses jq when present; otherwise emits a minimal, still-valid degraded object.
_skc_emit_json() {
  local dir="$1" profile="$2" chash="$3" files="$4" pcount="$5" signal="$6"
  local hits_tmp="$7" secret_tmp="$8"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

  if command -v jq >/dev/null 2>&1; then
    local hits_json secret_json
    hits_json="$(jq -R -s '
      split("\n") | map(select(length>0)) | map(split(""))
      | map({category:.[0], severity:.[1], file:.[2],
             line:((.[3]|tonumber?) // .[3]), role:.[4], excerpt:.[5]})' "$hits_tmp")"
    secret_json="$(jq -R -s '
      split("\n") | map(select(length>0)) | map(split(""))
      | map({category:.[0], file:.[1], line:((.[2]|tonumber?) // .[2]), masked:.[3]})' "$secret_tmp")"
    jq -n \
      --arg sv "$(patterns::schema_version)" --arg td "$dir" --arg prof "$profile" \
      --arg ch "$chash" --argjson fs "${files:-0}" --argjson pc "${pcount:-0}" \
      --arg sig "$signal" --argjson hits "$hits_json" --argjson secrets "$secret_json" \
      --arg ts "$ts" \
      '{schema_version:$sv, tool:"skill-screen", target_dir:$td, profile:$prof,
        content_hash:$ch, files_scanned:$fs, pattern_count:$pc,
        candidate_signal:$sig, hits:$hits, secret_hits:$secrets, scanned_at:$ts}'
  else
    # Degraded path: no jq. Counts only, no per-hit detail (still valid JSON).
    # grep -c prints "0" and exits 1 on no match; `|| true` keeps that "0" without
    # appending a second one (the earlier `|| echo 0` produced a stray "0\n0").
    local nhits nsec dir_esc
    nhits="$(grep -c . "$hits_tmp" 2>/dev/null || true)"; nhits="${nhits:-0}"
    nsec="$(grep -c . "$secret_tmp" 2>/dev/null || true)"; nsec="${nsec:-0}"
    # target_dir is operator-controlled; escape \ and " and drop control chars so a
    # crafted directory name cannot break the JSON in this hand-built path.
    dir_esc="$(printf '%s' "$dir" | tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"schema_version":"%s","tool":"skill-screen","target_dir":"%s",' \
      "$(patterns::schema_version)" "$dir_esc"
    printf '"profile":"%s","content_hash":"%s","files_scanned":%s,"pattern_count":%s,' \
      "$profile" "$chash" "${files:-0}" "${pcount:-0}"
    printf '"candidate_signal":"%s","hits_count":%s,"secret_hits_count":%s,' \
      "$signal" "$nhits" "$nsec"
    printf '"degraded":"jq not found: counts only","scanned_at":"%s"}\n' "$ts"
  fi
}

# scan::run <dir> <profile> <with_jp:0|1> <secret:0|1> <json_out_path>
# Writes the result JSON to <json_out_path> and sets global SKC_SIGNAL to one of:
#   no_signal | review_needed | do_not_install | scan-error
scan::run() {
  local dir="$1" profile="$2" with_jp="$3" secret="$4" out="$5"
  SKC_SIGNAL="scan-error"
  SKC_INCOMPLETE=0

  if [ ! -d "$dir" ]; then
    _skc_emit_json "$dir" "$profile" "sha256:unavailable" 0 0 "scan-error" /dev/null /dev/null > "$out"
    return 0
  fi

  local hits_tmp secret_tmp; hits_tmp="$(mktemp)"; secret_tmp="$(mktemp)"
  SKC_BADNAME_FLAG="$(mktemp)"
  local files_scanned content_hash pattern_count
  files_scanned="$(scan::list_files "$dir" | grep -c . || true)"
  content_hash="$(scan::content_hash "$dir")"
  pattern_count="$(patterns::category_count "$([ "$with_jp" = 1 ] && echo --with-jp)")"

  local rel entry category rest severity regex matches rc line content excerpt role
  while IFS= read -r rel; do
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      category="${entry%%|*}"; rest="${entry#*|}"
      severity="${rest%%|*}"; regex="${rest#*|}"
      matches="$(timeout "$SKC_GREP_TIMEOUT" grep -nIE -- "$regex" "$dir/$rel" 2>/dev/null)"; rc=$?
      [ "$rc" -eq 124 ] && SKC_INCOMPLETE=1
      [ -z "$matches" ] && continue
      printf '%s\n' "$matches" | head -n "$SKC_MATCH_CAP" | while IFS= read -r m; do
        [ -z "$m" ] && continue
        line="${m%%:*}"; content="${m#*:}"
        excerpt="$(_skc_sanitize "$content")"
        role="$(profiles::role "$rel" "$profile")"
        printf '%s\037%s\037%s\037%s\037%s\037%s\n' \
          "$category" "$severity" "$rel" "$line" "$role" "$excerpt" >> "$hits_tmp"
      done
    done < <(patterns::all_patterns "$([ "$with_jp" = 1 ] && echo --with-jp)")

    if [ "$secret" = 1 ]; then
      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        category="${entry%%|*}"; rest="${entry#*|}"; regex="${rest#*|}"
        matches="$(timeout "$SKC_GREP_TIMEOUT" grep -nIE -- "$regex" "$dir/$rel" 2>/dev/null)"; rc=$?
        [ "$rc" -eq 124 ] && SKC_INCOMPLETE=1
        [ -z "$matches" ] && continue
        printf '%s\n' "$matches" | head -n "$SKC_MATCH_CAP" | while IFS= read -r m; do
          [ -z "$m" ] && continue
          line="${m%%:*}"; content="${m#*:}"
          _skc_has_placeholder "$content" && continue
          local token; token="$(printf '%s' "$content" | grep -oE -- "$regex" 2>/dev/null | head -n1)"
          printf '%s\037%s\037%s\037%s\n' \
            "$category" "$rel" "$line" "$(_skc_mask "$token")" >> "$secret_tmp"
        done
      done < <(patterns::secret_patterns)
    fi
  done < <(scan::list_files "$dir")

  # signal: fail-closed on incomplete scan or control-char/escaping filenames.
  # severity is field 2 (US-delimited); awk -F'\037' interprets the octal escape,
  # whereas grep would not treat \037 as the US byte. If awk is unavailable we
  # fail closed: any hit at all is treated as blocked rather than silently downgraded.
  local has_blocked=0
  if command -v awk >/dev/null 2>&1; then
    awk -F'\037' '$2=="blocked"{found=1} END{exit(found?0:1)}' "$hits_tmp" 2>/dev/null && has_blocked=1
  elif [ -s "$hits_tmp" ]; then
    has_blocked=1
  fi
  local signal="no_signal"
  if [ -s "$secret_tmp" ] || [ "$has_blocked" = 1 ] \
     || [ "$SKC_INCOMPLETE" = 1 ] || [ -s "$SKC_BADNAME_FLAG" ]; then
    signal="do_not_install"
  elif [ -s "$hits_tmp" ]; then
    signal="review_needed"
  fi
  SKC_SIGNAL="$signal"

  _skc_emit_json "$dir" "$profile" "$content_hash" "$files_scanned" \
    "$pattern_count" "$signal" "$hits_tmp" "$secret_tmp" > "$out"
  rm -f "$hits_tmp" "$secret_tmp" "$SKC_BADNAME_FLAG"
}
