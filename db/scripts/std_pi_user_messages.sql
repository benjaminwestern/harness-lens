CREATE OR REPLACE VIEW std_pi_user_messages AS
SELECT 'pi' as harness, CAST(e.filename AS VARCHAR) as filename,
  COALESCE(string_split(MAX(CAST(e.cwd AS VARCHAR)) OVER (PARTITION BY e.filename), '/')[-1], split_part(string_split(CAST(e.filename AS VARCHAR), '/')[-2], '--', 2)) as project,
  CAST(e.cwd AS VARCHAR) as session_cwd,
  epoch_ms(try_cast(e.timestamp AS TIMESTAMP)) as ts,
  COALESCE(json_extract_string(e.message, '$.content'), CAST(json_extract(e.message, '$.content') AS VARCHAR)) as text
FROM read_json('{{sql .Home}}/.pi/agent/sessions/*/*.jsonl', format='auto', columns={'type':'VARCHAR', 'message':'JSON', 'cwd':'VARCHAR', 'timestamp':'VARCHAR'}, filename=true, ignore_errors=true) e
WHERE json_extract_string(e.message, '$.role') = 'user'
  AND COALESCE(json_extract_string(e.message, '$.content'), CAST(json_extract(e.message, '$.content') AS VARCHAR)) IS NOT NULL;
