# Sample corpus

Labeled fixtures used by `tests/test-scan.sh` to validate the Stage 1 scanner.

⚠️ The `malicious/` fixtures contain **simulated** attack text and one **fake**
(non-real) credential. They are inert example skills — nothing here executes, and the
credential is not valid. They exist only so the scanner has something to catch.

## Layout

Each fixture is a small skill directory (`SKILL.md`, sometimes a `scripts/` file).

- `malicious/` — fixtures the scanner should flag (`review_needed` or `do_not_install`).
- `benign/` — fixtures that should stay quiet (`no_signal`), **plus** `attack-docs`,
  a legitimate skill that *documents* attacks. Stage 1 deliberately flags it
  (`do_not_install`) because it cannot tell documentation from intent — that is the
  false positive Stage 2 (the LLM prompt) is designed to clear.

## Expected results

`EXPECTED.tsv` is the source of truth (tab-separated):

| column | meaning |
|---|---|
| `path` | fixture dir relative to `corpus/` |
| `flags` | extra flags to pass (e.g. `--with-jp`, `--include-secret-scan`); `-` = none (a TSV-safe stand-in for an empty field) |
| `expected_signal` | expected Stage 1 `candidate_signal` |
| `kind` | `malicious_tp` / `benign_clean` / `benign_doc_fp` |
| `note` | short description |

`malicious_tp` rows whose `expected_signal` is `review_needed` (not `do_not_install`)
are cases where Stage 1 only emits warnings by design; intent is confirmed at Stage 2.
