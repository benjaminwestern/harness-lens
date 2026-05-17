CREATE OR REPLACE VIEW std_gemini_message_events AS
WITH gemini_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, unnest(from_json(CAST(messages AS VARCHAR), '["JSON"]')) as msg
  FROM read_json('{{sql .Home}}/.gemini/tmp/*/chats/*.json', format='auto', columns={'messages': 'JSON'}, filename=true, ignore_errors=true)
)
SELECT 'gemini' as harness, filename,
  COALESCE(string_split(filename, '/')[-3], 'gemini') as project,
  json_extract_string(msg, '$.model') as raw_model,
  json_extract_string(msg, '$.model') as model,
  COALESCE(p.provider, 'google') as provider,
  CAST(NULL AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(json_extract_string(msg, '$.timestamp') AS TIMESTAMP)) as ts,
  CASE WHEN json_extract_string(msg, '$.model') IS NOT NULL THEN
    (coalesce(try_cast(json_extract_string(msg, '$.tokens.input') AS BIGINT), 0) * coalesce(p.input_cost, 0) + coalesce(try_cast(json_extract_string(msg, '$.tokens.output') AS BIGINT), 0) * coalesce(p.output_cost, 0) + coalesce(try_cast(json_extract_string(msg, '$.tokens.cached') AS BIGINT), 0) * coalesce(p.cache_cost, 0)) / 1000000.0
  ELSE 0.0 END as cost,
  coalesce(try_cast(json_extract_string(msg, '$.tokens.input') AS BIGINT), 0) as in_tok,
  coalesce(try_cast(json_extract_string(msg, '$.tokens.output') AS BIGINT), 0) as out_tok,
  coalesce(try_cast(json_extract_string(msg, '$.tokens.cached') AS BIGINT), 0) as cache_tok,
  CASE WHEN json_extract_string(msg, '$.type') = 'gemini' THEN 1 ELSE 0 END as is_turn,
  CASE WHEN json_extract_string(msg, '$.type') = 'user' THEN 1 ELSE 0 END as is_user,
  0 as is_tool,
  0 as is_error,
  CAST(NULL AS VARCHAR) as tool
FROM gemini_raw
LEFT JOIN api_pricing p ON p.model_key = json_extract_string(msg, '$.model')
WHERE json_extract_string(msg, '$.type') IN ('user', 'gemini');
