CREATE OR REPLACE VIEW std_gemini_user_messages AS
WITH gemini_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, unnest(from_json(CAST(messages AS VARCHAR), '["JSON"]')) as msg
  FROM read_json('{{sql .Home}}/.gemini/tmp/*/chats/*.json', format='auto', columns={'messages': 'JSON'}, filename=true, ignore_errors=true)
)
SELECT 'gemini' as harness, filename,
  COALESCE(string_split(filename, '/')[-3], 'gemini') as project,
  CAST(NULL AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(json_extract_string(msg, '$.timestamp') AS TIMESTAMP)) as ts,
  COALESCE(json_extract_string(msg, '$.content'), CAST(json_extract(msg, '$.content') AS VARCHAR)) as text
FROM gemini_raw
WHERE json_extract_string(msg, '$.type') = 'user'
  AND COALESCE(json_extract_string(msg, '$.content'), CAST(json_extract(msg, '$.content') AS VARCHAR)) IS NOT NULL;
