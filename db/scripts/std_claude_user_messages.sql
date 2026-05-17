CREATE OR REPLACE VIEW std_claude_user_messages AS
WITH claude_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, type, timestamp, cwd, isMeta, message
  FROM read_json('{{sql .Home}}/.claude/projects/**/*.jsonl', format='auto', columns={'type':'VARCHAR', 'timestamp':'VARCHAR', 'cwd':'VARCHAR', 'isMeta':'BOOLEAN', 'message':'JSON'}, filename=true, ignore_errors=true)
),
claude_norm AS (
  SELECT filename, type, timestamp, cwd, isMeta, message,
    MAX(cwd) FILTER (WHERE cwd IS NOT NULL) OVER (PARTITION BY filename) as session_cwd
  FROM claude_raw
)
SELECT 'claude' as harness, filename,
  COALESCE(string_split(session_cwd, '/')[-1], string_split(filename, '/')[-2], 'claude') as project,
  session_cwd,
  epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
  COALESCE(json_extract_string(message, '$.content'), CAST(json_extract(message, '$.content') AS VARCHAR)) as text
FROM claude_norm
WHERE type = 'user'
  AND NOT coalesce(isMeta, false)
  AND NOT (json_type(json_extract(message, '$.content')) = 'ARRAY' AND CAST(json_extract(message, '$.content') AS VARCHAR) LIKE '%"tool_result"%')
  AND COALESCE(json_extract_string(message, '$.content'), CAST(json_extract(message, '$.content') AS VARCHAR)) IS NOT NULL;
