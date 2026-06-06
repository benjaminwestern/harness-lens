CREATE OR REPLACE VIEW std_codex_user_messages AS
WITH codex_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, timestamp, type, payload
  FROM read_json('{{sql .Home}}/.codex/sessions/**/*.jsonl', format='auto', columns={'timestamp':'VARCHAR', 'type':'VARCHAR', 'payload':'JSON'}, filename=true, ignore_errors=true)
),
codex_norm AS (
  SELECT filename, timestamp, type, payload,
    MAX(json_extract_string(payload, '$.cwd')) FILTER (WHERE type = 'session_meta') OVER (PARTITION BY filename) as cwd
  FROM codex_raw
),
content_items AS (
  SELECT filename, timestamp, cwd, payload,
    unnest(from_json(CAST(json_extract(payload, '$.content') AS VARCHAR), '["JSON"]')) as item
  FROM codex_norm
  WHERE type = 'response_item'
    AND json_extract_string(payload, '$.type') = 'message'
    AND json_extract_string(payload, '$.role') = 'user'
    AND json_extract(payload, '$.content') IS NOT NULL
)
SELECT 'codex' as harness, filename,
  COALESCE(string_split(NULLIF(cwd, ''), '/')[-1], 'codex') as project,
  COALESCE(NULLIF(cwd, ''), 'codex') as session_cwd,
  epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
  json_extract_string(item, '$.text') as text
FROM content_items
WHERE json_extract_string(item, '$.type') = 'input_text'
  AND json_extract_string(item, '$.text') IS NOT NULL
  AND json_extract_string(item, '$.text') NOT LIKE '<environment_context>%'
  AND json_extract_string(item, '$.text') NOT LIKE '<permissions instructions>%'
  AND json_extract_string(item, '$.text') NOT LIKE '<collaboration_mode>%'
  AND json_extract_string(item, '$.text') NOT LIKE '<skills_instructions>%'
  AND json_extract_string(item, '$.text') NOT LIKE '# AGENTS.md%'
  AND json_extract_string(item, '$.text') NOT LIKE '<INSTRUCTIONS>%';
