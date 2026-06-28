# skill-screen

A **local, transparent** pre-install safety screen for third-party AI agent skills
(Claude Code skills, Codex extensions).

> Status: tested core. The Stage 1 engine and the labeled corpus pass the full
> dry-run suite (`tests/test-scan.sh`); the license is MIT. Not yet published, and
> the repo name is still tentative — a companion write-up is in progress.

## Why

Before you drop a skill you found on GitHub or a gist into `~/.claude/skills/`, you are
trusting its `SKILL.md` and scripts with whatever your agent can do. Official
marketplaces screen their own listings, but **there is no built-in check for a
skill you install yourself**.

`skill-screen` fills that gap with two deliberate properties:

- **Local-complete** — it never sends your skill anywhere. Everything runs on your
  machine. No account, no upload, no telemetry.
- **Transparent** — the entire detection logic is plain `grep` patterns you can read
  in `lib/patterns.sh`. There is no model and no black box in the mechanical stage.

It does **not** try to out-feature commercial scanners. The point is trust: you can
read every rule, and nothing leaves your laptop.

## How it works — inspection and interpretation are separate

1. **Stage 1 (mechanical, `grep`)** — `bin/skill-screen` walks the skill directory and
   matches a fixed, readable set of prompt-injection / risky-behavior patterns. It
   emits a machine-readable JSON verdict. High recall by design (it flags candidates;
   it does not decide intent).
2. **Stage 2 (interpretation, optional)** — hand `prompts/stage2-interpret.md` plus the
   Stage 1 JSON to an LLM (or read it yourself) to separate true positives from skills
   that merely *document* attacks. The prompt treats the skill as **data** and is
   instructed not to follow any instructions inside it.

### Verdicts (not safety guarantees)

| verdict | meaning |
|---|---|
| `no_signal` | no patterns matched. **Not** a proof of safety — just nothing the rules caught. |
| `review_needed` | warning-level matches; read them before installing. |
| `do_not_install` | blocked-level matches (instruction override, `curl\|bash`, etc.). |

## Usage

```sh
bin/skill-screen --target /path/to/some-skill            # human-readable verdict
bin/skill-screen --target /path/to/some-skill --json     # machine-readable JSON
bin/skill-screen --target ./suspect --quarantine         # move flagged skill aside
```

Requirements: `bash`, `grep`, `sha256sum`. `jq` is used for clean JSON output; without
it the tool degrades safely.

## Limitations (read these)

`skill-screen` is a screen, not a proof. Known boundaries by design:

- **`no_signal` is not "safe."** It means no rule matched what was scanned.
- **Binary files are hashed but not pattern-scanned.** A payload hidden in a binary
  blob won't be matched by the text rules (it is still part of `content_hash`).
- **Symlinks that escape the target are flagged, not followed.** A skill whose
  `SKILL.md` points outside its own directory is reported as `do_not_install` rather
  than read (this both closes a scan-bypass and avoids reading files outside the
  target). In-tree symlinks to regular files are scanned normally.
- **Stage 1 is high-recall.** It flags skills that merely *document* attacks too;
  Stage 2 (the LLM prompt) is what separates intent from documentation.
- **Pattern coverage is intentionally small and English/Japanese only.** A screen you
  can fully read beats a sprawling list you can't audit.

## License

See [LICENSE](LICENSE).
