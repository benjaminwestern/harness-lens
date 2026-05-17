CREATE OR REPLACE VIEW std_codex_user_messages AS
WITH codex_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, timestamp, type, payload
  FROM read_json('{{sql .Home}}/.codex/sessions/**/*.jsonl', format='auto', columns={'timestamp':'VARCHAR', 'type':'VARCHAR', 'payload':'JSON'}, filename=true, ignore_errors=true)
),
codex_norm AS (
  SELECT filename, timestamp, type, payload,
    MAX(json_extract_string(payload, '$.cwd')) FILTER (WHERE type = 'session_meta') OVER (PARTITION BY filename) as cwd
  FROM codex_raw
)
SELECT 'codex' as harness, filename,
  COALESCE(string_split(cwd, '/')[-1], 'codex') as project,
  cwd as session_cwd,
  epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
  COALESCE(json_extract_string(payload, '$.content[0].text'), CAST(json_extract(payload, '$.content') AS VARCHAR)) as text
FROM codex_norm
WHERE type = 'response_item'
  AND json_extract_string(payload, '$.type') = 'message'
  AND json_extract_string(payload, '$.role') = 'user'
  AND COALESCE(json_extract_string(payload, '$.content[0].text'), CAST(json_extract(payload, '$.content') AS VARCHAR)) IS NOT NULL
  AND COALESCE(json_extract_string(payload, '$.content[0].text'), '') NOT LIKE '<environment_context>%'
  AND COALESCE(json_extract_string(payload, '$.content[0].text'), '') NOT LIKE '<permissions instructions>%';
