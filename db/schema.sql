CREATE TABLE api_pricing (
  model_key TEXT NOT NULL,
  provider TEXT NOT NULL,
  input_cost FLOAT8 NOT NULL,
  output_cost FLOAT8 NOT NULL,
  cache_cost FLOAT8 NOT NULL,
  cache_write_cost FLOAT8
);

CREATE TABLE t_unified_events (
  harness TEXT NOT NULL,
  filename TEXT NOT NULL,
  project TEXT,
  raw_model TEXT,
  model TEXT,
  provider TEXT,
  session_cwd TEXT,
  ts BIGINT NOT NULL,
  cost FLOAT8 NOT NULL,
  in_tok BIGINT NOT NULL,
  out_tok BIGINT NOT NULL,
  cache_tok BIGINT NOT NULL,
  is_turn INTEGER NOT NULL,
  is_user INTEGER NOT NULL,
  is_tool INTEGER NOT NULL,
  is_error INTEGER NOT NULL,
  tool TEXT
);

CREATE TABLE t_session_model_stats_raw (
  harness TEXT NOT NULL,
  filename TEXT NOT NULL,
  raw_model TEXT,
  model TEXT,
  provider TEXT,
  turns BIGINT NOT NULL,
  cost FLOAT8 NOT NULL,
  in_tok BIGINT NOT NULL,
  out_tok BIGINT NOT NULL,
  cache_tok BIGINT NOT NULL,
  tools BIGINT NOT NULL,
  errors BIGINT NOT NULL
);

CREATE TABLE t_model_tools (
  harness TEXT NOT NULL,
  filename TEXT NOT NULL,
  model TEXT,
  provider TEXT,
  tool TEXT,
  count BIGINT NOT NULL,
  errors BIGINT NOT NULL
);

CREATE TABLE t_profanity_hits_attributed (
  hit_id BIGINT NOT NULL,
  harness TEXT NOT NULL,
  filename TEXT NOT NULL,
  project TEXT,
  ts BIGINT,
  word TEXT NOT NULL,
  group_name TEXT NOT NULL,
  severity TEXT NOT NULL,
  model TEXT,
  provider TEXT
);

CREATE TABLE t_sessions (
  harness TEXT NOT NULL,
  filename TEXT NOT NULL,
  start_time BIGINT NOT NULL,
  end_time BIGINT NOT NULL,
  duration_sec BIGINT NOT NULL,
  project TEXT,
  cwd TEXT,
  models JSON,
  cost FLOAT8 NOT NULL,
  in_tok BIGINT NOT NULL,
  out_tok BIGINT NOT NULL,
  cache_tok BIGINT NOT NULL,
  user_turns BIGINT NOT NULL,
  agent_turns BIGINT NOT NULL,
  errors BIGINT NOT NULL,
  tool_count BIGINT NOT NULL,
  tool_error_count BIGINT NOT NULL,
  tool_breakdown JSON,
  tool_error_breakdown JSON,
  model_tool_breakdown JSON,
  model_stats JSON
);
