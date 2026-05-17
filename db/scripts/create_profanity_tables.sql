BEGIN TRANSACTION;
CREATE OR REPLACE TABLE t_profanity_hits (
  hit_id BIGINT,
  harness VARCHAR,
  filename VARCHAR,
  project VARCHAR,
  ts BIGINT,
  word VARCHAR,
  group_name VARCHAR,
  severity VARCHAR
);

CREATE OR REPLACE TABLE t_profanity_hits_attributed AS
SELECT hit_id, harness, filename, project, ts, word, group_name, severity,
  CAST(NULL AS VARCHAR) as model,
  CAST(NULL AS VARCHAR) as provider
FROM t_profanity_hits;
COMMIT;
