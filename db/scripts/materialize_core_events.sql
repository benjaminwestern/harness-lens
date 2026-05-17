BEGIN TRANSACTION;
CREATE OR REPLACE TABLE t_unified_events_next (
  harness VARCHAR,
  filename VARCHAR,
  project VARCHAR,
  raw_model VARCHAR,
  model VARCHAR,
  provider VARCHAR,
  session_cwd VARCHAR,
  ts BIGINT,
  cost DOUBLE,
  in_tok BIGINT,
  out_tok BIGINT,
  cache_tok BIGINT,
  is_turn INTEGER,
  is_user INTEGER,
  is_tool INTEGER,
  is_error INTEGER,
  tool VARCHAR
);
{{range .Views}}
INSERT INTO t_unified_events_next SELECT * FROM {{ident .}};
{{end}}
CREATE OR REPLACE TABLE t_unified_events AS SELECT * FROM t_unified_events_next;
DROP TABLE IF EXISTS t_unified_events_next;
COMMIT;
