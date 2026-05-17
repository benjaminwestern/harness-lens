BEGIN TRANSACTION;
CREATE OR REPLACE TABLE t_session_model_stats_raw_next AS SELECT * FROM v_session_model_stats_raw;
CREATE OR REPLACE TABLE t_model_tools_next AS SELECT * FROM v_model_tools;
CREATE OR REPLACE TABLE t_sessions_next AS SELECT * FROM v_sessions;

CREATE OR REPLACE TABLE t_session_model_stats_raw AS SELECT * FROM t_session_model_stats_raw_next;
CREATE OR REPLACE TABLE t_model_tools AS SELECT * FROM t_model_tools_next;
CREATE OR REPLACE TABLE t_sessions AS SELECT * FROM t_sessions_next;

DROP TABLE IF EXISTS t_session_model_stats_raw_next;
DROP TABLE IF EXISTS t_model_tools_next;
DROP TABLE IF EXISTS t_sessions_next;
COMMIT;
