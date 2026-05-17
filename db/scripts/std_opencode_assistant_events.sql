CREATE OR REPLACE VIEW std_opencode_assistant_events AS
SELECT 'opencode' as harness, CAST(m.session_id AS VARCHAR) as filename,
  COALESCE(string_split(COALESCE(json_extract_string(m.data, '$.path.cwd'), s.directory), '/')[-1], 'opencode') as project,
  json_extract_string(m.data, '$.modelID') as raw_model,
  json_extract_string(m.data, '$.modelID') as model,
  COALESCE(json_extract_string(m.data, '$.providerID'), p.provider, 'opencode') as provider,
  COALESCE(json_extract_string(m.data, '$.path.cwd'), s.directory) as session_cwd,
  CAST(m.time_created AS BIGINT) as ts,
  CASE WHEN try_cast(json_extract_string(m.data, '$.cost') AS DOUBLE) IS NULL OR try_cast(json_extract_string(m.data, '$.cost') AS DOUBLE) = 0 THEN
    (
      COALESCE(try_cast(json_extract_string(m.data, '$.tokens.input') AS BIGINT), 0) * COALESCE(p.input_cost, 0) +
      COALESCE(try_cast(json_extract_string(m.data, '$.tokens.cache.write') AS BIGINT), 0) * COALESCE(p.cache_write_cost, p.input_cost, 0) +
      COALESCE(try_cast(json_extract_string(m.data, '$.tokens.output') AS BIGINT), 0) * COALESCE(p.output_cost, 0) +
      COALESCE(try_cast(json_extract_string(m.data, '$.tokens.cache.read') AS BIGINT), 0) * COALESCE(p.cache_cost, 0)
    ) / 1000000.0
  ELSE try_cast(json_extract_string(m.data, '$.cost') AS DOUBLE) END as cost,
  COALESCE(try_cast(json_extract_string(m.data, '$.tokens.input') AS BIGINT), 0) + COALESCE(try_cast(json_extract_string(m.data, '$.tokens.cache.write') AS BIGINT), 0) as in_tok,
  COALESCE(try_cast(json_extract_string(m.data, '$.tokens.output') AS BIGINT), 0) as out_tok,
  COALESCE(try_cast(json_extract_string(m.data, '$.tokens.cache.read') AS BIGINT), 0) as cache_tok,
  1 as is_turn,
  0 as is_user,
  0 as is_tool,
  0 as is_error,
  CAST(NULL AS VARCHAR) as tool
FROM opencode.message m
LEFT JOIN opencode.session s ON s.id = m.session_id
LEFT JOIN v_pricing_map p ON p.model = json_extract_string(m.data, '$.modelID')
WHERE m.data LIKE '{"role":"assistant"%';
