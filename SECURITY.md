# Security

Harness Lens is a local-first analytics tool for AI coding harness data. It is
built to run on your own machine, read local session files, and render a private
server-side dashboard.

## Current controls

- The HTTP server binds to `127.0.0.1:8080` by default. Set `HOST=0.0.0.0` only
  when you intentionally want another device to reach the dashboard.
- Mutating endpoints reject cross-origin browser requests and reject non-loopback
  Host headers by default. Set `HARNESS_LENS_ALLOW_REMOTE_WRITES=1` only if you
  understand the risk of remote writes.
- Runtime analytics use an in-memory DuckDB database. Harness Lens does not write
  a DuckDB database file by default.
- User-message text is extracted transiently for profanity aggregation and then
  dropped. The persisted output is aggregate profanity data, not raw transcript
  text.
- Uploaded profanity dictionaries are local files under
  `~/.config/harness-lens/custom-dictionary.csv`.

## Trust model

Harness Lens assumes your local harness transcripts are trusted local files. Do
not point it at untrusted directories or run it on a shared network interface
unless you have added an external access-control boundary.

## Out of scope

This public prototype does not provide authentication, TLS, multi-user access
control, filesystem sandboxing, or resource limits. Put it behind a trusted local
boundary before using it as a shared service.
