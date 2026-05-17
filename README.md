# harness-lens

A local-first Go dashboard for inspecting AI coding-agent sessions across the
harnesses you run on your own machine.

Harness Lens reads local session stores, normalises them through DuckDB, and
renders a server-side dashboard for spend, tokens, models, providers, tools,
errors, timelines, session drilldowns, and aggregate profanity signals.

## Status

This is a public prototype, not a stable product release. The first public push
is intended to make the idea inspectable, runnable, and safe enough for local
use. The data model and UI are still allowed to change while the shape settles.

The current build is strong enough to show:

- A single local dashboard across Pi, OpenCode, Claude, Codex, and Gemini.
- DuckDB-backed ELT into unified event, session, model, tool, and profanity
  aggregate tables.
- Server-rendered Go templates with small HTML fragments streamed over SSE.
- Local-only defaults, with no runtime DuckDB file written by default.
- Profanity aggregation without persisting raw user-message text.
- CSV dictionary upload/download for local custom profanity detection.

## Quick start

Install repo-local tools, run the verification suite, then start the dashboard:

```bash
mise trust       # only needed if mise asks you to trust this config
mise install     # installs Go, hk, pkl, sqlc, golangci-lint, and gofumpt
mise run check
mise run build
./harness-lens
```

Open the local dashboard:

```text
http://127.0.0.1:8080
```

Harness Lens starts the HTTP server before the first DuckDB refresh completes.
The first page shows a processing state while local transcripts are read into an
in-memory database. The dashboard updates automatically when the first refresh
finishes.

## Supported harnesses

Harness Lens discovers these stores automatically when they exist:

| Harness | Source | Notes |
| --- | --- | --- |
| Pi | `~/.pi/agent/sessions/*/*.jsonl` | Reads session events, token usage, tool calls, and user messages for aggregate profanity counts. |
| OpenCode | `~/.local/share/opencode/opencode.db` | Attaches the SQLite database read-only through DuckDB's sqlite extension. |
| Claude | `~/.claude/projects/**/*.jsonl` | Reads assistant usage, tool results, project paths, and user-message aggregates. |
| Codex | `~/.codex/sessions/**/*.jsonl` | Reads assistant turns, model usage, tool events, and user-message aggregates. |
| Gemini | `~/.gemini/tmp/*/chats/*.json` | Reads chat messages and tool events from local Gemini chat files. |

Pricing data is loaded from `https://models.dev/api.json` into DuckDB at startup
so raw token counts can be converted into estimated spend where the local
harness did not already record a cost.

## How it works

```mermaid
flowchart LR
    Sources[Local harness stores] --> DuckDB[DuckDB in memory]
    DuckDB --> Std[std_* event views]
    Std --> Unified[t_unified_events]
    Unified --> Sessions[t_sessions]
    Unified --> Models[t_session_model_stats_raw]
    Unified --> Tools[t_model_tools]
    Sources --> UserMsgs[transient user messages]
    UserMsgs --> Profanity[t_profanity_hits_attributed]
    Sessions --> Templates[Go html/template]
    Models --> Templates
    Tools --> Templates
    Profanity --> Templates
    Templates --> Browser[Local browser]
    Browser --> SSE[/events HTML fragments]
```

The important boundary is that DuckDB owns filtering, sorting, and aggregation.
The browser receives rendered HTML and minimal canvas chart data. There is no
frontend framework, no polling loop, and no cloud service.

Refreshes are serialised. While an ETL refresh swaps materialised tables, page
queries wait for a consistent snapshot instead of reading a half-updated set of
tables.

## Privacy model

Harness Lens is designed for local inspection, not hosted analytics.

- The server binds to `127.0.0.1:8080` by default.
- Runtime analytics use DuckDB `:memory:` and are not written to a database file.
- Raw user-message text is read transiently for profanity aggregation, then the
  transient table is dropped after refresh.
- The retained profanity output is aggregate data: counts, severities, groups,
  harness, session, model, and provider attribution.
- Uploaded profanity dictionaries are stored locally at
  `~/.config/harness-lens/custom-dictionary.csv`.

To expose the dashboard beyond localhost, opt in explicitly:

```bash
HOST=0.0.0.0 PORT=8080 ./harness-lens
```

Write endpoints still reject non-loopback Host headers by default. Only set this
when you are adding your own network boundary:

```bash
HARNESS_LENS_ALLOW_REMOTE_WRITES=1 HOST=0.0.0.0 ./harness-lens
```

## Profanity analytics

The profanity side takes massive inspiration from
[devrage](https://github.com/benjaminwestern/devrage): a local, aggregate-first
way to notice friction and frustration in coding-agent sessions. Harness Lens is
not a port of devrage. It folds that idea into the DuckDB dashboard so profanity
can be correlated with harness, model, provider, session, tool usage, and time.

The built-in dictionary is intentionally small and editable. Download the
built-in template from the Profanity page, edit it, then upload a CSV with this
shape:

```csv
word,severity,group
fuck,strong,fuck
shit,strong,shit
wtf,mild,wtf
```

`severity` must be `mild`, `moderate`, or `strong`. `group` defaults to the word
when omitted. Duplicate words are normalised and deduplicated, with the last row
winning. In `extend` mode, custom entries override built-ins. In `replace` mode,
only the uploaded CSV is used.

You can also configure a dictionary by environment variable:

```bash
HARNESS_LENS_DICTIONARY=/path/to/custom.csv HARNESS_LENS_DICTIONARY_MODE=extend ./harness-lens
```

The older `DEVRAGE_DICTIONARY`, `PROFANITY_DICTIONARY`, and
`DEVRAGE_DICTIONARY_MODE` names are still read as compatibility fallbacks.

## Development workflow

This repo intentionally uses local verification instead of GitHub Actions. The
same checks are exposed through mise tasks and hk hooks.

```bash
mise run hk:install      # install git hooks
mise run check:quick     # fast local gate
mise run check           # full local gate
mise run hk:check        # run hk's default check profile
mise run go:fmt          # apply configured Go formatters
mise run sqlc:generate   # regenerate db/*.sql.go after query changes
```

The main task map follows the same style as my other Go repos:

| Task | Purpose |
| --- | --- |
| `mise run build` | Build `./harness-lens`. |
| `mise run go:lint` | Run `golangci-lint run` with `.golangci.yaml`. |
| `mise run web:smoke` | Build a temporary binary and curl the local dashboard routes. |
| `mise run check` | Run the full local pre-push-quality suite. |

## Troubleshooting setup

If the first command fails before Go code runs, refresh the local toolchain and
validate the repository wiring:

```bash
mise doctor
mise install
mise run mise:validate
mise run hk:validate
hk --version
pkl --version
sqlc version
golangci-lint version
go version
```

DuckDB extension installation can need network access the first time it loads
`httpfs` or `sqlite`. After that, startup should be local apart from pricing data
from `models.dev`.

## Repository notes

Generated sqlc files under `db/*.sql.go` are checked in so the project builds
without requiring sqlc at runtime. Source queries live under `db/queries/` and
schema hints live in `db/schema.sql`.

Do not commit local binaries, logs, screenshots, or private harness transcripts.
The `.gitignore` file excludes the common local build artefacts for this repo.
