CREATE OR REPLACE VIEW std_pi_user_messages AS
SELECT 'pi' as harness, CAST(e.filename AS VARCHAR) as filename,
  COALESCE(string_split(MAX(CAST(e.cwd AS VARCHAR)) OVER (PARTITION BY e.filename), '/')[-1], split_part(string_split(CAST(e.filename AS VARCHAR), '/')[-2], '--', 2)) as project,
  CAST(e.cwd AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(e.timestamp AS TIMESTAMP)) as ts,
  json_extract_string(t.block, '$.text') as text
FROM read_json('{{sql .Home}}/.pi/agent/sessions/*/*.jsonl', format='auto', columns={'type':'VARCHAR', 'message':'JSON', 'cwd':'VARCHAR', 'timestamp':'VARCHAR'}, filename=true, ignore_errors=true) e,
  unnest(from_json(CAST(COALESCE(json_extract(e.message, '$.content'), '[]') AS VARCHAR), '["JSON"]')) as t(block)
WHERE json_extract_string(e.message, '$.role') = 'user'
  AND json_extract_string(t.block, '$.type') = 'text'
  AND json_extract_string(t.block, '$.text') IS NOT NULL;
