# Third-party licenses

`skill-checker` bundles **no third-party code**. The repository ships only its own
source (`bin/`, `lib/`, `prompts/`, `corpus/`, `tests/`), licensed under MIT
(see [LICENSE](LICENSE)).

## Runtime requirements (not bundled)

The tool calls the following programs from the host system at runtime. They are
**not** distributed with this repository; each retains its own license on your
machine.

| Tool | Role | Required |
|---|---|---|
| `bash` | runtime shell | yes |
| `grep` | Stage 1 pattern matching | yes |
| `sha256sum` | `content_hash` | yes |
| `jq` | clean JSON output (degrades safely without it) | optional |

Because there are no bundled dependencies, there is nothing further to audit here.
This file exists for consistency with the project's license-check process; if a
third-party dependency is ever added, record it above with its SPDX identifier.
