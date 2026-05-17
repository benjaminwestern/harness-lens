CREATE OR REPLACE VIEW std_opencode_user_messages AS
SELECT 'opencode' as harness, CAST(m.session_id AS VARCHAR) as filename,
  COALESCE(string_split(s.directory, '/')[-1], 'opencode') as project,
  s.directory as session_cwd,
  CAST(m.time_created AS BIGINT) as ts,
  json_extract_string(p.data, '$.text') as text
FROM opencode.message m
JOIN opencode.session s ON s.id = m.session_id
JOIN opencode.part p ON p.message_id = m.id
WHERE m.data LIKE '{"role":"user"%'
  AND json_extract_string(p.data, '$.type') = 'text'
  AND json_extract_string(p.data, '$.text') IS NOT NULL;
