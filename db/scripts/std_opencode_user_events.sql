CREATE OR REPLACE VIEW std_opencode_user_events AS
SELECT 'opencode' as harness, CAST(m.session_id AS VARCHAR) as filename,
  COALESCE(string_split(s.directory, '/')[-1], 'opencode') as project,
  CAST(NULL AS VARCHAR) as raw_model,
  CAST(NULL AS VARCHAR) as model,
  CAST(NULL AS VARCHAR) as provider,
  s.directory as session_cwd,
  CAST(m.time_created AS BIGINT) as ts,
  0.0 as cost,
  0 as in_tok,
  0 as out_tok,
  0 as cache_tok,
  0 as is_turn,
  1 as is_user,
  0 as is_tool,
  0 as is_error,
  CAST(NULL AS VARCHAR) as tool
FROM opencode.message m
JOIN opencode.session s ON s.id = m.session_id
WHERE m.data LIKE '{"role":"user"%';
