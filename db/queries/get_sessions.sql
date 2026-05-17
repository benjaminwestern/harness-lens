-- name: GetSessions :many
WITH base AS (
  SELECT 
    harness,
    filename,
    strftime(to_timestamp(start_time/1000)::TIMESTAMP, '%Y-%m-%dT%H:%M:%S.%f')::text as start_time_str,
    strftime(to_timestamp(end_time/1000)::TIMESTAMP, '%Y-%m-%dT%H:%M:%S.%f')::text as end_time_str,
    date_diff('second', to_timestamp(start_time/1000)::TIMESTAMP, to_timestamp(end_time/1000)::TIMESTAMP)::bigint as duration_sec_calc,
    project,
    cwd,
    cost,
    in_tok,
    out_tok,
    cache_tok,
    (in_tok + out_tok + cache_tok)::bigint as total_tokens,
    user_turns,
    agent_turns,
    (user_turns + agent_turns)::bigint as total_turns,
    errors,
    tool_count,
    tool_error_count,
    tool_breakdown::text as tool_breakdown_json,
    tool_error_breakdown::text as tool_error_breakdown_json,
    model_tool_breakdown::text as model_tool_breakdown_json,
    model_stats::text as model_stats_json,
    COALESCE(to_json(models)::text, '[]')::text as models_json,
    start_time,
    end_time,
    duration_sec
  FROM t_sessions s
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.provider = sqlc.arg(provider)))
    AND (sqlc.arg(model)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.model = sqlc.arg(model)))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = s.harness AND e.filename = s.filename AND e.tool = sqlc.arg(tool)))
)
SELECT
  harness,
  filename,
  start_time_str,
  end_time_str,
  duration_sec_calc,
  project,
  cwd,
  cost,
  in_tok,
  out_tok,
  cache_tok,
  total_tokens,
  user_turns,
  agent_turns,
  total_turns,
  errors,
  tool_count,
  tool_error_count,
  tool_breakdown_json,
  tool_error_breakdown_json,
  model_tool_breakdown_json,
  model_stats_json,
  models_json,
  printf('$%.4f', cost)::text as cost_display,
  CASE WHEN total_tokens < 1000 THEN CAST(total_tokens AS VARCHAR) WHEN total_tokens < 1000000 THEN printf('%.1fK', total_tokens / 1000.0) WHEN total_tokens < 1000000000 THEN printf('%.1fM', total_tokens / 1000000.0) ELSE printf('%.1fB', total_tokens / 1000000000.0) END::text as total_tokens_display,
  (CASE WHEN in_tok < 1000 THEN CAST(in_tok AS VARCHAR) WHEN in_tok < 1000000 THEN printf('%.1fK', in_tok / 1000.0) WHEN in_tok < 1000000000 THEN printf('%.1fM', in_tok / 1000000.0) ELSE printf('%.1fB', in_tok / 1000000000.0) END || ' in / ' ||
   CASE WHEN out_tok < 1000 THEN CAST(out_tok AS VARCHAR) WHEN out_tok < 1000000 THEN printf('%.1fK', out_tok / 1000.0) WHEN out_tok < 1000000000 THEN printf('%.1fM', out_tok / 1000000.0) ELSE printf('%.1fB', out_tok / 1000000000.0) END || ' out / ' ||
   CASE WHEN cache_tok < 1000 THEN CAST(cache_tok AS VARCHAR) WHEN cache_tok < 1000000 THEN printf('%.1fK', cache_tok / 1000.0) WHEN cache_tok < 1000000000 THEN printf('%.1fM', cache_tok / 1000000.0) ELSE printf('%.1fB', cache_tok / 1000000000.0) END || ' cache')::text as token_breakdown_display,
  CASE WHEN duration_sec_calc <= 0 THEN '-' WHEN duration_sec_calc < 60 THEN CAST(duration_sec_calc AS VARCHAR) || 's' WHEN duration_sec_calc < 3600 THEN CAST(CAST(floor(duration_sec_calc / 60) AS BIGINT) AS VARCHAR) || 'm ' || CAST(duration_sec_calc % 60 AS VARCHAR) || 's' ELSE CAST(CAST(floor(duration_sec_calc / 3600) AS BIGINT) AS VARCHAR) || 'h ' || CAST(CAST(floor((duration_sec_calc % 3600) / 60) AS BIGINT) AS VARCHAR) || 'm' END::text as duration_display,
  CASE WHEN tool_count = 0 THEN '0%' ELSE printf('%.1f%%', tool_error_count * 100.0 / tool_count) END::text as tool_error_pct
FROM base
ORDER BY
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'when' AND sqlc.arg(sort_dir)::text = 'asc' THEN start_time END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'when' AND sqlc.arg(sort_dir)::text = 'desc' THEN start_time END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'project' AND sqlc.arg(sort_dir)::text = 'asc' THEN project END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'project' AND sqlc.arg(sort_dir)::text = 'desc' THEN project END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'asc' THEN cost END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'desc' THEN cost END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'tokens' AND sqlc.arg(sort_dir)::text = 'asc' THEN in_tok + out_tok + cache_tok END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'tokens' AND sqlc.arg(sort_dir)::text = 'desc' THEN in_tok + out_tok + cache_tok END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'duration' AND sqlc.arg(sort_dir)::text = 'asc' THEN duration_sec END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'duration' AND sqlc.arg(sort_dir)::text = 'desc' THEN duration_sec END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'turns' AND sqlc.arg(sort_dir)::text = 'asc' THEN agent_turns END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'sessions' AND sqlc.arg(sort_by)::text = 'turns' AND sqlc.arg(sort_dir)::text = 'desc' THEN agent_turns END DESC,
  start_time DESC
LIMIT 100;
