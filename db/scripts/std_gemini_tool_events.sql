CREATE OR REPLACE VIEW std_gemini_tool_events AS
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
  epoch_ms(try_cast(json_extract_string(tc, '$.timestamp') AS TIMESTAMP)) as ts,
  0.0 as cost, 0 as in_tok, 0 as out_tok, 0 as cache_tok,
  0 as is_turn, 0 as is_user, 1 as is_tool,
  CASE WHEN json_extract_string(tc, '$.status') = 'error' THEN 1 ELSE 0 END as is_error,
  CAST(json_extract_string(tc, '$.name') AS VARCHAR) as tool
FROM (
  SELECT filename, msg, unnest(from_json(CAST(json_extract(msg, '$.toolCalls') AS VARCHAR), '["JSON"]')) as tc
  FROM gemini_raw WHERE json_extract(msg, '$.toolCalls') IS NOT NULL AND json_extract_string(msg, '$.toolCalls') != 'null'
)
LEFT JOIN api_pricing p ON p.model_key = json_extract_string(msg, '$.model')
WHERE json_extract_string(tc, '$.name') IS NOT NULL;
