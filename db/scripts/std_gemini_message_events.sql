CREATE OR REPLACE VIEW std_gemini_message_events AS
WITH gemini_raw AS (
  SELECT * FROM read_json('{{sql .Home}}/.gemini/tmp/*/chats/*', format='auto', columns={
    'sessionId': 'VARCHAR', 'projectHash': 'VARCHAR', 'messages': 'JSON',
    'id': 'VARCHAR', 'type': 'VARCHAR', 'timestamp': 'VARCHAR', 'content': 'JSON',
    'model': 'VARCHAR', 'tokens': 'JSON', 'toolCalls': 'JSON', 'thoughts': 'JSON'
  }, filename=true, ignore_errors=true)
),
gemini_json AS (
  SELECT filename, unnest(from_json(CAST(messages AS VARCHAR), '["JSON"]')) as msg
  FROM gemini_raw WHERE messages IS NOT NULL
),
gemini_jsonl AS (
  SELECT filename, {'id': id, 'type': type, 'timestamp': timestamp, 'content': content, 'model': model, 'tokens': tokens, 'toolCalls': toolCalls, 'thoughts': thoughts} as msg
  FROM gemini_raw WHERE id IS NOT NULL
),
gemini_all AS (
  SELECT * FROM gemini_json UNION ALL SELECT * FROM gemini_jsonl
)
SELECT 'gemini' as harness, CAST(e.filename AS VARCHAR) as filename,
  COALESCE(string_split(e.filename, '/')[-3], 'gemini') as project,
  json_extract_string(e.msg, '$.model') as raw_model,
  json_extract_string(e.msg, '$.model') as model,
  COALESCE(p.provider, 'google') as provider,
  CAST(NULL AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(json_extract_string(e.msg, '$.timestamp') AS TIMESTAMP)) as ts,
  CASE WHEN json_extract_string(e.msg, '$.model') IS NOT NULL THEN
    (coalesce(try_cast(json_extract_string(e.msg, '$.tokens.input') AS BIGINT), 0) * coalesce(p.input_cost, 0) +
     coalesce(try_cast(json_extract_string(e.msg, '$.tokens.output') AS BIGINT), 0) * coalesce(p.output_cost, 0) +
     coalesce(try_cast(json_extract_string(e.msg, '$.tokens.cached') AS BIGINT), 0) * coalesce(p.cache_cost, 0) +
     coalesce(try_cast(json_extract_string(e.msg, '$.tokens.thoughts') AS BIGINT), 0) * coalesce(p.output_cost, 0) +
     coalesce(try_cast(json_extract_string(e.msg, '$.tokens.tool') AS BIGINT), 0) * coalesce(p.input_cost, 0)
    ) / 1000000.0
  ELSE 0.0 END as cost,
  coalesce(try_cast(json_extract_string(e.msg, '$.tokens.input') AS BIGINT), 0) + coalesce(try_cast(json_extract_string(e.msg, '$.tokens.tool') AS BIGINT), 0) as in_tok,
  coalesce(try_cast(json_extract_string(e.msg, '$.tokens.output') AS BIGINT), 0) + coalesce(try_cast(json_extract_string(e.msg, '$.tokens.thoughts') AS BIGINT), 0) as out_tok,
  coalesce(try_cast(json_extract_string(e.msg, '$.tokens.cached') AS BIGINT), 0) as cache_tok,
  CASE WHEN json_extract_string(e.msg, '$.type') = 'gemini' THEN 1 ELSE 0 END as is_turn,
  CASE WHEN json_extract_string(e.msg, '$.type') = 'user' THEN 1 ELSE 0 END as is_user,
  0 as is_tool,
  0 as is_error,
  CAST(NULL AS VARCHAR) as tool
FROM gemini_all e
LEFT JOIN api_pricing p ON p.model_key = json_extract_string(e.msg, '$.model')
WHERE json_extract_string(e.msg, '$.type') IN ('user', 'gemini');
