SELECT harness, filename, project, ts, text FROM t_user_messages WHERE text IS NOT NULL AND text != '';
