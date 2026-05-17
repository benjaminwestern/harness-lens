CREATE OR REPLACE VIEW std_pi_events AS
SELECT 'pi' as harness, CAST(e.filename AS VARCHAR) as filename,
  COALESCE(string_split(MAX(CAST(e.cwd AS VARCHAR)) OVER (PARTITION BY e.filename), '/')[-1], split_part(string_split(CAST(e.filename AS VARCHAR), '/')[-2], '--', 2)) as project,
  json_extract_string(e.message, '$.model') as raw_model,
  json_extract_string(e.message, '$.model') as model,
  COALESCE(json_extract_string(e.message, '$.provider'), 'unknown') as provider,
  CAST(e.cwd AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(e.timestamp AS TIMESTAMP)) as ts,
  CASE WHEN try_cast(json_extract_string(e.message, '$.usage.cost.total') AS DOUBLE) IS NULL OR try_cast(json_extract_string(e.message, '$.usage.cost.total') AS DOUBLE) = 0 THEN
    (coalesce(try_cast(json_extract_string(e.message, '$.usage.input') AS BIGINT), 0) * coalesce(p.input_cost, 0) + coalesce(try_cast(json_extract_string(e.message, '$.usage.output') AS BIGINT), 0) * coalesce(p.output_cost, 0) + coalesce(try_cast(json_extract_string(e.message, '$.usage.cacheRead') AS BIGINT), 0) * coalesce(p.cache_cost, 0)) / 1000000.0
  ELSE try_cast(json_extract_string(e.message, '$.usage.cost.total') AS DOUBLE) END as cost,
  coalesce(try_cast(json_extract_string(e.message, '$.usage.input') AS BIGINT), 0) as in_tok,
  coalesce(try_cast(json_extract_string(e.message, '$.usage.output') AS BIGINT), 0) as out_tok,
  coalesce(try_cast(json_extract_string(e.message, '$.usage.cacheRead') AS BIGINT), 0) as cache_tok,
  CASE WHEN json_extract_string(e.message, '$.role') = 'assistant' THEN 1 ELSE 0 END as is_turn,
  CASE WHEN json_extract_string(e.message, '$.role') = 'user' THEN 1 ELSE 0 END as is_user,
  CASE WHEN json_extract_string(e.message, '$.role') = 'toolResult' AND json_extract_string(e.message, '$.toolName') IS NOT NULL THEN 1 ELSE 0 END as is_tool,
  CASE WHEN json_extract_string(e.message, '$.role') = 'toolResult' AND try_cast(json_extract_string(e.message, '$.isError') AS BOOLEAN) THEN 1 ELSE 0 END as is_error,
  json_extract_string(e.message, '$.toolName') as tool
FROM read_json('{{sql .Home}}/.pi/agent/sessions/*/*.jsonl', format='auto', columns={'type':'VARCHAR', 'message':'JSON', 'cwd':'VARCHAR', 'timestamp':'VARCHAR'}, filename=true, ignore_errors=true) e
LEFT JOIN v_pricing_map p ON p.model = json_extract_string(e.message, '$.model')
WHERE e.message IS NOT NULL OR CAST(e.type AS VARCHAR) = 'session';
