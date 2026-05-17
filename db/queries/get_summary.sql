-- name: GetSummary :one
WITH filtered AS (
  SELECT *
  FROM t_sessions s
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = sqlc.arg(harness) AND e.harness = s.harness AND e.filename = s.filename))
    AND (sqlc.arg(provider)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.provider = sqlc.arg(provider)))
    AND (sqlc.arg(model)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.model = sqlc.arg(model)))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = s.harness AND e.filename = s.filename AND e.tool = sqlc.arg(tool)))
),
agg AS (
  SELECT
    COALESCE(SUM(cost), 0)::float8 as total_spend,
    COALESCE(SUM(in_tok + out_tok), 0)::bigint as total_tokens,
    COALESCE(SUM(in_tok), 0)::bigint as in_tokens,
    COALESCE(SUM(out_tok), 0)::bigint as out_tokens,
    COALESCE(SUM(cache_tok), 0)::bigint as cache_tokens,
    COUNT(DISTINCT filename)::bigint as sessions,
    CAST(COALESCE(AVG(CASE WHEN duration_sec > 0 AND duration_sec < 86400 THEN duration_sec END), 0) AS BIGINT) as avg_duration,
    COUNT(CASE WHEN duration_sec > 0 AND duration_sec < 86400 THEN 1 END)::bigint as timed_sessions,
    COALESCE(SUM(tool_count), 0)::bigint as tool_calls,
    COALESCE(SUM(tool_error_count), 0)::bigint as tool_errors,
    COALESCE(SUM(agent_turns), 0)::bigint as agent_turns,
    COALESCE(SUM(user_turns), 0)::bigint as user_turns,
    COUNT(CASE WHEN json_array_length(models) > 1 THEN 1 END)::bigint as multi_model_sessions
  FROM filtered
),
derived AS (
  SELECT *,
    (agent_turns + user_turns)::bigint as total_turns,
    CASE WHEN (agent_turns + user_turns) = 0 THEN 0 ELSE CAST(total_tokens / (agent_turns + user_turns) AS BIGINT) END as avg_tokens_per_turn
  FROM agg
)
SELECT
  total_spend,
  total_tokens,
  in_tokens,
  out_tokens,
  cache_tokens,
  sessions,
  avg_duration,
  timed_sessions,
  tool_calls,
  tool_errors,
  agent_turns,
  user_turns,
  multi_model_sessions,
  printf('$%.2f', total_spend)::text as total_spend_display,
  CASE WHEN total_tokens < 1000 THEN CAST(total_tokens AS VARCHAR) WHEN total_tokens < 1000000 THEN printf('%.1fK', total_tokens / 1000.0) WHEN total_tokens < 1000000000 THEN printf('%.1fM', total_tokens / 1000000.0) ELSE printf('%.1fB', total_tokens / 1000000000.0) END::text as total_tokens_display,
  (CASE WHEN in_tokens < 1000 THEN CAST(in_tokens AS VARCHAR) WHEN in_tokens < 1000000 THEN printf('%.1fK', in_tokens / 1000.0) WHEN in_tokens < 1000000000 THEN printf('%.1fM', in_tokens / 1000000.0) ELSE printf('%.1fB', in_tokens / 1000000000.0) END || ' in / ' ||
   CASE WHEN out_tokens < 1000 THEN CAST(out_tokens AS VARCHAR) WHEN out_tokens < 1000000 THEN printf('%.1fK', out_tokens / 1000.0) WHEN out_tokens < 1000000000 THEN printf('%.1fM', out_tokens / 1000000.0) ELSE printf('%.1fB', out_tokens / 1000000000.0) END || ' out / ' ||
   CASE WHEN cache_tokens < 1000 THEN CAST(cache_tokens AS VARCHAR) WHEN cache_tokens < 1000000 THEN printf('%.1fK', cache_tokens / 1000.0) WHEN cache_tokens < 1000000000 THEN printf('%.1fM', cache_tokens / 1000000.0) ELSE printf('%.1fB', cache_tokens / 1000000000.0) END || ' cache')::text as token_breakdown_display,
  CASE WHEN sessions = 0 THEN '0%' ELSE printf('%.1f%%', multi_model_sessions * 100.0 / sessions) END::text as multi_model_sessions_pct,
  CASE WHEN avg_duration <= 0 THEN '-' WHEN avg_duration < 60 THEN CAST(avg_duration AS VARCHAR) || 's' WHEN avg_duration < 3600 THEN CAST(CAST(floor(avg_duration / 60) AS BIGINT) AS VARCHAR) || 'm ' || CAST(avg_duration % 60 AS VARCHAR) || 's' ELSE CAST(CAST(floor(avg_duration / 3600) AS BIGINT) AS VARCHAR) || 'h ' || CAST(CAST(floor((avg_duration % 3600) / 60) AS BIGINT) AS VARCHAR) || 'm' END::text as avg_duration_display,
  CASE WHEN tool_calls < 1000 THEN CAST(tool_calls AS VARCHAR) WHEN tool_calls < 1000000 THEN printf('%.1fK', tool_calls / 1000.0) WHEN tool_calls < 1000000000 THEN printf('%.1fM', tool_calls / 1000000.0) ELSE printf('%.1fB', tool_calls / 1000000000.0) END::text as tool_calls_display,
  CASE WHEN tool_errors < 1000 THEN CAST(tool_errors AS VARCHAR) WHEN tool_errors < 1000000 THEN printf('%.1fK', tool_errors / 1000.0) WHEN tool_errors < 1000000000 THEN printf('%.1fM', tool_errors / 1000000.0) ELSE printf('%.1fB', tool_errors / 1000000000.0) END::text as tool_errors_display,
  CASE WHEN tool_calls = 0 THEN '0%' ELSE printf('%.1f%%', tool_errors * 100.0 / tool_calls) END::text as tool_error_pct,
  CASE WHEN sessions = 0 THEN '$0.00' ELSE printf('$%.2f', total_spend / sessions) END::text as avg_cost_per_session_display,
  total_turns,
  CASE WHEN avg_tokens_per_turn < 1000 THEN CAST(avg_tokens_per_turn AS VARCHAR) WHEN avg_tokens_per_turn < 1000000 THEN printf('%.1fK', avg_tokens_per_turn / 1000.0) WHEN avg_tokens_per_turn < 1000000000 THEN printf('%.1fM', avg_tokens_per_turn / 1000000.0) ELSE printf('%.1fB', avg_tokens_per_turn / 1000000000.0) END::text as avg_tokens_per_turn_display,
  CASE WHEN sessions = 0 THEN '0' ELSE printf('%.1f', tool_calls * 1.0 / sessions) END::text as avg_tools_per_session_display
FROM derived;
