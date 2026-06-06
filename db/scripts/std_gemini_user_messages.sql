CREATE OR REPLACE VIEW std_gemini_user_messages AS
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
),
content_parts AS (
  SELECT e.filename, e.msg, unnest(from_json(CAST(json_extract(e.msg, '$.content') AS VARCHAR), '["JSON"]')) as part
  FROM gemini_all e
  WHERE json_extract(e.msg, '$.content') IS NOT NULL
)
SELECT 'gemini' as harness, CAST(e.filename AS VARCHAR) as filename,
  COALESCE(string_split(e.filename, '/')[-3], 'gemini') as project,
  CAST(NULL AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(json_extract_string(e.msg, '$.timestamp') AS TIMESTAMP)) as ts,
  json_extract_string(part, '$.text') as text
FROM content_parts e
WHERE json_extract_string(e.msg, '$.type') = 'user'
  AND json_extract_string(part, '$.text') IS NOT NULL;
