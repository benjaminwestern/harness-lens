CREATE OR REPLACE VIEW std_opencode_tool_events AS
SELECT 'opencode' as harness, CAST(p.session_id AS VARCHAR) as filename,
  COALESCE(string_split(COALESCE(json_extract_string(m.data, '$.path.cwd'), s.directory), '/')[-1], 'opencode') as project,
  json_extract_string(m.data, '$.modelID') as raw_model,
  json_extract_string(m.data, '$.modelID') as model,
  COALESCE(json_extract_string(m.data, '$.providerID'), pm.provider, 'opencode') as provider,
  COALESCE(json_extract_string(m.data, '$.path.cwd'), s.directory) as session_cwd,
  CAST(p.time_created AS BIGINT) as ts,
  0.0 as cost,
  0 as in_tok,
  0 as out_tok,
  0 as cache_tok,
  0 as is_turn,
  0 as is_user,
  1 as is_tool,
  CASE WHEN json_extract_string(p.data, '$.state.status') IN ('error', 'failed') THEN 1 ELSE 0 END as is_error,
  CAST(json_extract_string(p.data, '$.tool') AS VARCHAR) as tool
FROM (SELECT message_id, session_id, time_created, data FROM opencode.part WHERE data LIKE '{"type":"tool"%') p
JOIN opencode.message m ON m.id = p.message_id
LEFT JOIN opencode.session s ON s.id = p.session_id
LEFT JOIN v_pricing_map pm ON pm.model = json_extract_string(m.data, '$.modelID')
WHERE json_extract_string(p.data, '$.tool') IS NOT NULL;
