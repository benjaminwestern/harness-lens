-- name: GetProfanitySummary :one
WITH filtered_sessions AS (
  SELECT *
  FROM t_sessions s
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR s.project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR s.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR s.harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.provider = sqlc.arg(provider)))
    AND (sqlc.arg(model)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.model = sqlc.arg(model)))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_model_tools mt WHERE mt.harness = s.harness AND mt.filename = s.filename AND mt.tool = sqlc.arg(tool)))
),
filtered_hits AS (
  SELECT h.*
  FROM t_profanity_hits_attributed h
  JOIN filtered_sessions s ON s.harness = h.harness AND s.filename = h.filename
  WHERE (sqlc.arg(provider)::text = '' OR h.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR h.model = sqlc.arg(model))
),
agg AS (
  SELECT
    (SELECT COUNT(*) FROM filtered_hits)::bigint as total_swears,
    (SELECT COUNT(*) FROM filtered_hits WHERE severity = 'strong')::bigint as strong_swears,
    (SELECT COUNT(DISTINCT harness || ':' || filename) FROM filtered_hits)::bigint as sessions_with_swears,
    (SELECT COUNT(*) FROM filtered_sessions)::bigint as sessions,
    COALESCE((SELECT SUM(user_turns) FROM filtered_sessions), 0)::bigint as user_turns,
    COALESCE((SELECT group_name FROM filtered_hits GROUP BY group_name ORDER BY COUNT(*) DESC, group_name LIMIT 1), '')::text as top_group
)
SELECT
  total_swears,
  strong_swears,
  sessions_with_swears,
  sessions,
  user_turns,
  top_group,
  CASE WHEN user_turns = 0 THEN '0.00' ELSE printf('%.2f', total_swears * 1.0 / user_turns) END::text as swears_per_user_turn_display,
  CASE WHEN sessions = 0 THEN '0.00' ELSE printf('%.2f', total_swears * 1.0 / sessions) END::text as swears_per_session_display,
  CASE WHEN sessions = 0 THEN '0%' ELSE printf('%.1f%%', sessions_with_swears * 100.0 / sessions) END::text as sessions_with_swears_pct
FROM agg;
