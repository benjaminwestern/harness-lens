CREATE OR REPLACE VIEW std_gemini_tool_events AS
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
  0.0 as cost, 0 as in_tok, 0 as out_tok, 0 as cache_tok,
  0 as is_turn, 0 as is_user, 1 as is_tool,
  CASE WHEN json_extract_string(tc.unnest, '$.status') = 'error' THEN 1 ELSE 0 END as is_error,
  CAST(json_extract_string(tc.unnest, '$.name') AS VARCHAR) as tool
FROM gemini_all e,
  unnest(from_json(CAST(json_extract(e.msg, '$.toolCalls') AS VARCHAR), '["JSON"]')) as tc
LEFT JOIN api_pricing p ON p.model_key = json_extract_string(e.msg, '$.model')
WHERE json_extract(e.msg, '$.toolCalls') IS NOT NULL
  AND json_extract_string(e.msg, '$.toolCalls') != 'null'
  AND json_extract_string(tc.unnest, '$.name') IS NOT NULL;
