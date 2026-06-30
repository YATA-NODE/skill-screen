# skill-screen

> This README is in English for precision. Prefer Japanese? Run it through a machine
> translator. (日本語が必要なら翻訳機にかけてください。精度のため英語で書いています。)

A local, transparent, **read-only** pre-install safety screen for third-party AI agent
skills (Claude Code and OpenAI Codex — the shared `SKILL.md` format). It scans every file
in a skill directory — not just `SKILL.md`, but any instruction files an agent reads
(`SKILL.md` / `AGENTS.md` / `CLAUDE.md`) and scripts too. The whole scanner is a single
script, `skill-screen`, readable top to bottom. It **never creates, moves, or deletes
your files** — it only reads and reports. No network, no account, no telemetry.

## Why

Before you drop a skill you found on GitHub or a gist into `~/.claude/skills/`, you are
trusting its `SKILL.md` and scripts with whatever your agent can do. Official marketplaces
screen their own listings, but there is no built-in check for a skill you install
yourself. `skill-screen` fills that gap with three deliberate properties:

- **Local-complete** — it never sends your skill anywhere. Everything runs on your machine.
  No account, no upload, no telemetry.
- **Read-only** — it never writes, moves, or deletes anything in your target. A freshly
  downloaded, not-yet-trusted tool that silently created or moved folders would itself be
  a red flag. Isolation is *your* manual step (see Usage), never the tool's.
- **Transparent** — the entire detection logic lives in the single `skill-screen` file:
  the **(1) DETECTION RULES** section (readable `grep` patterns) and the **(2) INSPECTION**
  section that applies them to every file. No model, no black box in the mechanical stage.
  To change a rule, edit section (1).

The point is trust: every rule lives in one file you can read, and nothing — no skill, no
metadata — ever leaves your machine.

## How it works — inspection and interpretation are separate

1. **Stage 1 (mechanical, `grep`)** — `skill-screen` walks the target directory and matches
   a fixed, readable set of prompt-injection / risky-behavior patterns, then emits a
   machine-readable JSON verdict. High recall by design (it flags candidates; it does not
   decide intent).
2. **Stage 2 (interpretation, optional)** — hand the Stage 1 JSON plus the flagged excerpts,
   together with the Stage 2 prompt in `SKILL.md`, to a capable LLM (or read it yourself) to
   separate true positives from skills that merely *document* attacks. The prompt treats the
   skill as data and refuses to follow instructions inside it.

### What it inspects (scan scope)

Every non-denylisted file is scanned, not just `SKILL.md` — including the skill's own scripts
(`.sh`, `.py`, `.js`, …), where a `curl|bash` installer or a credential exfil usually lives.
Each hit gets a `role` (`instruction` / `executable` / `other`) by extension alone; no tool's
instruction filename (`AGENTS.md`, `CLAUDE.md`, …) is special-cased. Denylisted noise
(`.git/`, `node_modules/`, `.env`) is skipped; binaries are hashed but not pattern-scanned
(see Limitations).

### Verdicts (not safety guarantees)

| verdict | meaning |
|---|---|
| `no_signal` | no patterns matched. Not a proof of safety — just nothing the rules caught. |
| `review_needed` | warning-level matches; read them before installing. |
| `do_not_install` | blocked-level matches (instruction override, `curl\|bash`, etc.). |

## Install (as an agent skill)

`skill-screen` is itself a skill folder. To let your agent run it automatically:

- Drop this whole folder into `~/.claude/skills/` (so you get
  `~/.claude/skills/skill-screen/SKILL.md` next to `.../skill-screen`).
- Already have your own `SKILL.md` setup? Append this `SKILL.md`'s body to yours and keep
  the `skill-screen` script beside it.

Or just run the script directly — it needs no installation (see Usage).

## Usage

```sh
./skill-screen --target /path/to/some-skill                       # human-readable verdict
./skill-screen --target /path/to/some-skill --json                # machine-readable JSON
./skill-screen --target /path/to/some-skill --include-secret-scan # also flag shipped credentials
```

**Isolation-first (manual):** keep an untrusted skill where you downloaded it (e.g.
`~/Downloads/`); do not move it into `~/.claude/skills/` until it clears. The tool never
moves it for you — scanning is read-only.

The Japanese warning patterns are applied **by default** (the primary audience is
Japanese); there is no opt-in flag.

### Options

| option | meaning |
|---|---|
| `--target <dir>` | directory of the skill/extension to screen (required) |
| `--include-secret-scan` | also scan for shipped credentials (masked in output) |
| `--json` | print the machine-readable JSON instead of a summary |

Requirements: `bash`, `grep`, `sha256sum`, `timeout` (coreutils). `jq` is used for clean
JSON output; without it the tool degrades safely.

## Limitations (read these)

`skill-screen` is a screen, not a proof. Known boundaries by design:

- `no_signal` is not "safe." It means no rule matched what was scanned.
- Binary files are hashed but not pattern-scanned. A payload hidden in a binary blob won't
  be matched by the text rules (it is still part of `content_hash`).
- Symlinks that escape the target are flagged, not followed: a skill whose `SKILL.md` points
  outside its own directory is reported as `do_not_install` rather than read.
- Stage 1 is high-recall. It flags skills that merely *document* attacks too; Stage 2 (the
  LLM prompt) separates intent from documentation.
- Pattern coverage is intentionally small and English/Japanese only. A screen you can fully
  read beats a sprawling list you can't audit.

## License

See [LICENSE](LICENSE) (MIT). Third-party notes: [LICENSES.md](LICENSES.md).
