BEGIN TRANSACTION;
CREATE OR REPLACE TABLE t_user_messages (
  harness VARCHAR,
  filename VARCHAR,
  project VARCHAR,
  session_cwd VARCHAR,
  ts BIGINT,
  text VARCHAR
);
{{range .Views}}
INSERT INTO t_user_messages SELECT * FROM {{ident .}};
{{end}}
COMMIT;
