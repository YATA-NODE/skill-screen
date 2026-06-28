# skill-screen

> 日本語 → English（同じ内容を日本語・英語の順で記載 / same content, Japanese first then English）

サードパーティ製の AI エージェント skill（Claude Code skill、Codex 拡張）を、インストール前に
チェックする **ローカル完結・透明** な安全スクリーン。

> ステータス: コアはテスト済み。Stage 1 エンジンとラベル付きコーパスは dry-run スイート
> （`tests/test-scan.sh`）を全て通過、ライセンスは MIT。未公開 — 解説記事を準備中。

## なぜ作ったか

GitHub や gist で見つけた skill を `~/.claude/skills/` に入れる時点で、その `SKILL.md` と
スクリプトに、あなたのエージェントができること全てを託すことになります。公式マーケット
プレイスは自分たちの掲載物は審査しますが、**自分で入れる skill を検査する仕組みは用意されて
いません**。

`skill-screen` はその隙間を、2 つの意図的な性質で埋めます:

- **ローカル完結（Local-complete）** — skill をどこにも送信しません。全てあなたのマシン上で
  動きます。アカウント不要・アップロードなし・テレメトリなし。
- **透明（Transparent）** — 検出ロジックの全ては `lib/patterns.sh` に書かれた、読める `grep`
  パターンです。機械的ステージにモデルもブラックボックスもありません。

既存の skill/agent スキャナ(OSS のものもあります)は、検査のためにアカウント登録や、スキル名・
メタデータのクラウド送信を必要とすることが多いです。`skill-screen` は機能数でそれらと張り合い
ません。要点は信頼です — 検出ルールは 1 ファイルで全部読め、スキルもメタデータも一切ラップ
トップの外に出ません(アカウント不要)。

## 仕組み — 検査と解釈の分離

1. **Stage 1（機械的、`grep`）** — `bin/skill-screen` が skill ディレクトリを走査し、固定
   された読めるルールセット（prompt-injection / 危険な振る舞い）を照合。machine-readable な
   JSON verdict を出力。設計上 高 recall（候補を挙げるだけで、意図は判断しない）。
2. **Stage 2（解釈、任意）** — `prompts/stage2-interpret.md` と Stage 1 の JSON を LLM に渡す
   （または自分で読む）ことで、true positive と「攻撃を*説明しているだけ*の skill」を切り分け
   る。プロンプトは skill を **データ** として扱い、その中の指示には従わないよう指示されている。

### 何を検査するか（範囲とプロファイル）

- **`SKILL.md` だけでなく、全ファイルを検査。** Stage 1 は対象全体を走査し、denylist 以外の
  *全*ファイルを grep します — skill 自身のスクリプトや実行ファイル（`.sh` / `.py` / `.js` …）
  も含みます（`curl|bash` インストーラや認証情報の流出は、たいていコード側に潜むため）。各 hit
  には `role`（`instruction` / `executable` / `other`）が付与され、prose 由来かコード由来かが
  分かります。ファイル型で走査を絞ることは意図的にしません — payload を予期せぬファイル型に
  隠させてしまうからです。（`.git/` / `node_modules/` / `.env` 等の denylist ノイズは除外。
  バイナリは hash 化のみで pattern 走査外 — *制限事項* 参照。）
- **プロファイルは自動判定**（`--profile` で上書き可）。判定は auto 検出と `role` ラベルにのみ
  影響し、*どのファイルを走査するか* は変えません:
  - `agent-skill` — トップレベルに `SKILL.md` がある。`SKILL.md` は **Claude Code と OpenAI
    Codex の両方が使う共通仕様**（open agent skills spec）なので、どちらのツールの skill も
    このプロファイルで扱う。
  - `codex-config` — `AGENTS.md` / `AGENTS.override.md` / `config.toml` / `.codex/config.toml`
    がある（かつ `SKILL.md` がない）。`AGENTS.md` は skill ではなく Codex の**カスタム指示**
    ファイルだが、エージェントが読むため検査対象にする。
  - `generic` — それ以外。全て走査し、拡張子だけで分類。

### verdict（安全保証ではない）

| verdict | 意味 |
|---|---|
| `no_signal` | どのパターンにも一致せず。**安全の証明ではない** — ルールが何も捕まえなかっただけ。 |
| `review_needed` | warning レベルの一致あり。インストール前に読むこと。 |
| `do_not_install` | blocked レベルの一致（instruction override、`curl\|bash` 等）。 |

## 使い方

```sh
bin/skill-screen --target /path/to/some-skill            # 人間向けの判定
bin/skill-screen --target /path/to/some-skill --json     # machine-readable な JSON
bin/skill-screen --target ./suspect --quarantine         # ./quarantine/ へ退避
bin/skill-screen --target ./suspect --quarantine=/tmp/q  # ...任意のディレクトリへ
```

### オプション

| オプション | 意味 |
|---|---|
| `--target <dir>` | 検査する skill/拡張のディレクトリ（必須） |
| `--profile <name>` | `auto`（既定）\| `agent-skill` \| `codex-config` \| `generic`（*何を検査するか* 参照） |
| `--with-jp` | 日本語の warning パターンも適用 |
| `--include-secret-scan` | 同梱された認証情報もスキャン（出力ではマスク） |
| `--quarantine[=<dir>]` | verdict が `no_signal`/`scan-error` 以外のとき、対象を退避。退避先の既定は `./quarantine/`、`--quarantine=<dir>` で指定可。退避コピー名は `<basename>-<short-hash>`。退避はヒューリスティックな処置であって**有罪の証明ではない** — 削除前に確認のこと。 |
| `--json` | サマリでなく machine-readable な JSON を出力 |

必要なもの: `bash`、`grep`、`sha256sum`、`timeout`（coreutils）。`jq` があれば JSON が整形
される（なくても安全に degrade）。

## 制限事項（必ず読むこと）

`skill-screen` はスクリーンであって証明ではありません。設計上の既知の境界:

- **`no_signal` は「安全」ではない。** 走査した範囲でルールが一致しなかった、という意味。
- **バイナリは hash 化されるが pattern 走査されない。** バイナリ blob に隠された payload は
  テキストルールに一致しない（ただし `content_hash` には含まれる）。
- **対象外へ逃げる symlink は、追従せず flag。** `SKILL.md` が自ディレクトリ外を指す skill は、
  読まずに `do_not_install` と報告（scan-bypass を塞ぎ、かつ対象外のファイルを読まない）。
  ツリー内の通常ファイルへの symlink は通常通り走査。
- **Stage 1 は高 recall。** 攻撃を*説明しているだけ*の skill も flag する。意図と説明の
  切り分けは Stage 2（LLM プロンプト）が行う。
- **パターン網羅は意図的に小さく、英語+日本語のみ。** 自分で読み切れるスクリーンは、読めない
  巨大リストに勝る。

## ライセンス

[LICENSE](LICENSE) を参照。

---

# English

A **local, transparent** pre-install safety screen for third-party AI agent skills
(Claude Code skills, Codex extensions).

> Status: tested core. The Stage 1 engine and the labeled corpus pass the full
> dry-run suite (`tests/test-scan.sh`); the license is MIT. Not yet published —
> a companion write-up is in progress.

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

Other skill/agent scanners exist — some are open source — but they typically need an
account and send your skills' names or metadata to a cloud service to run their checks.
`skill-screen` does **not** try to out-feature them. The point is trust: every rule lives
in one file you can read, and nothing — no skill, no metadata — ever leaves your machine
(no account required).

## How it works — inspection and interpretation are separate

1. **Stage 1 (mechanical, `grep`)** — `bin/skill-screen` walks the skill directory and
   matches a fixed, readable set of prompt-injection / risky-behavior patterns. It
   emits a machine-readable JSON verdict. High recall by design (it flags candidates;
   it does not decide intent).
2. **Stage 2 (interpretation, optional)** — hand `prompts/stage2-interpret.md` plus the
   Stage 1 JSON to an LLM (or read it yourself) to separate true positives from skills
   that merely *document* attacks. The prompt treats the skill as **data** and is
   instructed not to follow any instructions inside it.

### What it inspects (scope & profiles)

- **Every file is scanned, not just `SKILL.md`.** Stage 1 walks the whole target and
  greps *every* non-denylisted file — including the skill's own scripts and executables
  (`.sh`, `.py`, `.js`, …), which are where a `curl|bash` installer or a credential
  exfil usually lives. Each hit is labelled with a `role` (`instruction` / `executable`
  / `other`) so you can see whether a match came from prose or from code. Narrowing the
  scan by file type is deliberately *not* done — that would let a payload hide in an
  unexpected file. (Denylisted noise such as `.git/`, `node_modules/`, `.env` is skipped;
  binaries are hashed but not pattern-scanned — see *Limitations*.)
- **Profiles are auto-detected** (override with `--profile`). They only affect
  auto-detection and the `role` labels — never *which* files are scanned:
  - `agent-skill` — a `SKILL.md` is present at the top level. `SKILL.md` is the open
    agent skills spec used by **both Claude Code and OpenAI Codex**, so a skill from
    either tool uses this profile.
  - `codex-config` — an `AGENTS.md`, `AGENTS.override.md`, `config.toml`, or
    `.codex/config.toml` is present (and no `SKILL.md`). `AGENTS.md` is Codex's custom
    *instructions* file, **not** a skill, but an agent reads it so it is screened too.
  - `generic` — anything else; scan everything, classify by extension only.

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
bin/skill-screen --target ./suspect --quarantine         # move aside into ./quarantine/
bin/skill-screen --target ./suspect --quarantine=/tmp/q  # ...into a directory you choose
```

### Options

| option | meaning |
|---|---|
| `--target <dir>` | directory of the skill/extension to screen (required) |
| `--profile <name>` | `auto` (default) \| `agent-skill` \| `codex-config` \| `generic` (see *What it inspects*) |
| `--with-jp` | also apply the Japanese warning patterns |
| `--include-secret-scan` | also scan for shipped credentials (masked in output) |
| `--quarantine[=<dir>]` | if the verdict is not `no_signal`/`scan-error`, move the target aside. Default destination is `./quarantine/`; pass `--quarantine=<dir>` to choose another. The moved copy is named `<basename>-<short-hash>`. Quarantine is a heuristic action, **not** proof of malice — review before deleting. |
| `--json` | print the machine-readable JSON instead of a summary |

Requirements: `bash`, `grep`, `sha256sum`, `timeout` (coreutils). `jq` is used for clean
JSON output; without it the tool degrades safely.

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
