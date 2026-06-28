#!/usr/bin/env bash
# patterns.sh — the entire detection ruleset for skill-checker, in plain sight.
#
# This is the transparency promise of skill-checker: every rule that can flag a
# skill lives here, as a readable POSIX extended-regex (ERE). There is no hidden
# model and no remote service in the mechanical stage. Read it, audit it, fork it.
#
# Source-only (does not `set` anything, so it won't disturb a caller's `set -eu`).
#
# Format of each entry:  category|severity|extended-regex
#   - category : short stable id, shown in output and used by the stage-2 prompt
#   - severity : "blocked" (do not install) or "warning" (read before installing)
#   - regex    : matched with `grep -nE` against each scanned file
#
# Design notes (why the ruleset is small and conservative):
#   - High recall, deliberate false positives. Stage 1 flags *candidates*; a human
#     or an LLM (stage 2) decides intent. A skill that merely *documents* an attack
#     ("never write 'ignore previous instructions'") will match here — that is fine,
#     stage 2 sorts it out.
#   - Non-English (Japanese) patterns are warning-only. Vocabulary-based matching is
#     easy to evade by rewording, so a JP hit alone never escalates to "blocked".
#   - The list is intentionally NOT exhaustive across languages or phrasings. A
#     screen you can fully read beats a sprawling list you can't.

# Bump when the pattern set changes (recorded in scan output; used for re-check logic).
# v1 (skill-checker initial): EN blocked 3 + EN warning 5 + JP warning 4
patterns::schema_version() { echo "1"; }

# BLOCKED — install-blocking. Classic prompt-injection / remote code execution.
SKC_BLOCKED_PATTERNS=(
  'instruction-override|blocked|(ignore|disregard) (all |any )?(previous|prior|above|earlier) (instruction|prompt|direction|rule)|forget (everything|all|your) (prior|previous|instruction|rule)|override (the )?(system|previous|prior) (prompt|instruction)'
  'role-change|blocked|you are now (an?|the)|act as (an?|the|if)|pretend (to be|you are)|from now on,? you (are|will|must|should)|disregard your (role|persona|identity|instruction)'
  'remote-exec|blocked|(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)([[:space:]]|$)'
)

# WARNING (English) — legitimate uses exist; surface for a human read.
SKC_WARNING_PATTERNS=(
  'directive-injection|warning|^[[:space:]]*(system|assistant|developer)[[:space:]]*:'
  'secret-file-ref|warning|~/\.ssh/|~/\.aws/|/etc/(shadow|passwd)|(^|[^A-Za-z._])id_rsa([^A-Za-z]|$)|\.pem([^A-Za-z]|$)|\.p12([^A-Za-z]|$)|(^|[^A-Za-z.])\.env([^A-Za-z]|$)'
  'net-call-added|warning|(curl|wget)[[:space:]]|fetch\(|requests\.(get|post)|urllib\.request|http\.client|nc[[:space:]]+-'
  'suspicious-url|warning|(bit\.ly|tinyurl\.com|t\.co|is\.gd|goo\.gl|ow\.ly)/|aHR0c[A-Za-z0-9+/]{6,}'
  'rule-reversal|warning|(always|must)[[:space:]].{0,40}(never|must[[:space:]]not)|(security[_-]?review|fact[_-]?check|brand[_-]?check)[[:space:]].{0,24}(optional|skip|disable|unnecessary|not[[:space:]]+required)'
)

# WARNING (Japanese) — opt-in with --with-jp. Severity fixed to warning (see design note).
# Limited to the core 4: instruction override / role change / system-prompt reference /
# explicit role nullification. No open-ended multi-language expansion.
SKC_JP_WARNING_PATTERNS=(
  'instruction-override-jp|warning|(これまでの|以前の|上記の|前述の)[[:space:]]*(指示|命令|指令|指図|プロンプト|ルール).{0,8}(を)?[[:space:]]*(無視|忘れ|破棄|忘却|抹消|撤回)'
  'role-change-jp|warning|(以後|今後|これから)[[:space:]]*(あなたは|君は)'
  'system-prompt-ref-jp|warning|システムプロンプト(を|は|について|の内容)'
  'role-change-explicit-jp|warning|(役割|ロール|ペルソナ)[[:space:]]*(を)?[[:space:]]*(変更|変え|無効|無視)'
)

# SECRET markers — opt-in with --include-secret-scan. A skill that ships a real
# credential is a strong "do not install" signal (and a leak risk for the author).
# Matched values are masked before they ever appear in output (see scan.sh).
# Lines containing a placeholder word (EXAMPLE/DUMMY/TEST/SAMPLE/PLACEHOLDER/YOUR_/
# xxxxx) are skipped by scan.sh to cut documentation false positives.
SKC_SECRET_PATTERNS=(
  'aws-access-key|blocked|AKIA[0-9A-Z]{16}'
  'github-token|blocked|ghp_[A-Za-z0-9]{36}'
  'stripe-live|blocked|sk_live_[A-Za-z0-9]{16,}'
  'private-key-pem|blocked|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  'openai-key|blocked|sk-[A-Za-z0-9]{20,}'
  'slack-token|blocked|xox[baprs]-[A-Za-z0-9-]{10,}'
)

# patterns::secret_patterns — emit secret marker patterns, one per line.
patterns::secret_patterns() {
  local p
  for p in "${SKC_SECRET_PATTERNS[@]}"; do printf '%s\n' "$p"; done
}

# patterns::all_patterns [--with-jp]
# Emit every active pattern, one "category|severity|regex" per line.
patterns::all_patterns() {
  local with_jp=0
  [ "${1:-}" = "--with-jp" ] && with_jp=1
  local p
  for p in "${SKC_BLOCKED_PATTERNS[@]}"; do printf '%s\n' "$p"; done
  for p in "${SKC_WARNING_PATTERNS[@]}"; do printf '%s\n' "$p"; done
  if [ "$with_jp" -eq 1 ] && [ "${#SKC_JP_WARNING_PATTERNS[@]}" -gt 0 ]; then
    for p in "${SKC_JP_WARNING_PATTERNS[@]}"; do printf '%s\n' "$p"; done
  fi
}

# patterns::category_count [--with-jp] — number of active patterns (for scan output).
patterns::category_count() {
  patterns::all_patterns "${1:-}" | grep -c . || true
}
