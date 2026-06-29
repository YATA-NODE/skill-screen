#!/usr/bin/env bash
# test-scan.sh — dry-run validation of the Stage 1 scanner against the labeled corpus.
#
# Asserts, for every row in corpus/EXPECTED.tsv, that skill-screen's candidate_signal
# matches the expected value. Also checks content_hash stability and scan-error.
#
# Exit 0 = all pass, 1 = at least one failure.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$root/skill-screen"
expected="$root/corpus/EXPECTED.tsv"

# field_of <json_file> <key> -> string value of a top-level scalar key
field_of() {
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$2" "$1"
  else
    grep -oE "\"$2\":\"[^\"]*\"" "$1" | head -n1 | cut -d'"' -f4
  fi
}

say() { printf '%s\n' "$*"; }

results="$(mktemp)"

# --- table-driven cases (subshell pipeline -> write to results file) ---
tail -n +2 "$expected" | while IFS=$'\t' read -r path flags exp kind note; do
  [ -z "$path" ] && continue
  [ "$flags" = "-" ] && flags=""   # "-" sentinel = no extra flags (TSV-safe empty)
  out="$(mktemp)"
  # shellcheck disable=SC2086
  "$check" --target "$root/corpus/$path" $flags --json > "$out" 2>/dev/null
  got="$(field_of "$out" candidate_signal)"
  rm -f "$out"
  if [ "$got" = "$exp" ]; then
    printf 'PASS  %-34s (%s) -> %s\n' "$path" "$kind" "$got"
  else
    printf 'FAIL  %-34s (%s) expected=%s got=%s\n' "$path" "$kind" "$exp" "$got"
  fi
done >> "$results"

cat "$results"
pass="$(grep -c '^PASS' "$results" || true)"
fail="$(grep -c '^FAIL' "$results" || true)"
rm -f "$results"

say ""
say "--- aggregate checks ---"

# Recall sanity: the table must not declare a malicious_tp as no_signal.
# Columns: path<TAB>flags<TAB>expected_signal<TAB>kind<TAB>note
# awk (portable, exact tab fields) rather than grep -P (GNU-only; a -P-less grep
# would exit 2, get swallowed, and make this check silently pass).
if awk -F'\t' 'NR>1 && $3=="no_signal" && $4=="malicious_tp"{bad=1} END{exit(bad?0:1)}' "$expected"; then
  say "FAIL  recall: a malicious_tp row expects no_signal"; fail=$((fail+1))
else
  say "PASS  recall: every malicious_tp expects a non-quiet signal"
fi

# content_hash stability: same input -> same hash across two runs.
h1="$("$check" --target "$root/corpus/benign/normal-formatter" --json 2>/dev/null > "$results.a"; field_of "$results.a" content_hash)"
h2="$("$check" --target "$root/corpus/benign/normal-formatter" --json 2>/dev/null > "$results.b"; field_of "$results.b" content_hash)"
rm -f "$results.a" "$results.b"
if [ -n "$h1" ] && [ "$h1" = "$h2" ]; then
  say "PASS  content_hash stable ($h1)"
else
  say "FAIL  content_hash unstable ($h1 vs $h2)"; fail=$((fail+1))
fi

# scan-error: missing directory -> exit 3.
"$check" --target "$root/corpus/__does_not_exist__" --json >/dev/null 2>&1
rc=$?
if [ "$rc" = 3 ]; then
  say "PASS  scan-error on missing dir (exit 3)"
else
  say "FAIL  missing dir exit=$rc (expected 3)"; fail=$((fail+1))
fi

say ""
say "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
