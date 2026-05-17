-- name: GetProjects :many
WITH agg AS (
  SELECT s.project, COALESCE(SUM(s.cost), 0)::float8 as spend, COUNT(*)::bigint as sessions, COALESCE(AVG(CASE WHEN s.duration_sec > 0 AND s.duration_sec < 86400 THEN s.duration_sec END), 0)::bigint as avg_duration
  FROM t_sessions s
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR s.project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR s.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = sqlc.arg(harness) AND e.harness = s.harness AND e.filename = s.filename))
    AND (sqlc.arg(provider)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.provider = sqlc.arg(provider)))
    AND (sqlc.arg(model)::text = '' OR EXISTS (SELECT 1 FROM t_session_model_stats_raw sms WHERE sms.harness = s.harness AND sms.filename = s.filename AND sms.model = sqlc.arg(model)))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = s.harness AND e.filename = s.filename AND e.tool = sqlc.arg(tool)))
  GROUP BY s.project
)
SELECT
  project,
  spend,
  printf('$%.4f', spend)::text as spend_display,
  sessions,
  avg_duration,
  CASE WHEN avg_duration <= 0 THEN '-' WHEN avg_duration < 60 THEN CAST(avg_duration AS VARCHAR) || 's' WHEN avg_duration < 3600 THEN CAST(CAST(floor(avg_duration / 60) AS BIGINT) AS VARCHAR) || 'm ' || CAST(avg_duration % 60 AS VARCHAR) || 's' ELSE CAST(CAST(floor(avg_duration / 3600) AS BIGINT) AS VARCHAR) || 'h ' || CAST(CAST(floor((avg_duration % 3600) / 60) AS BIGINT) AS VARCHAR) || 'm' END::text as avg_duration_display
FROM agg
ORDER BY
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'project' AND sqlc.arg(sort_dir)::text = 'asc' THEN project END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'project' AND sqlc.arg(sort_dir)::text = 'desc' THEN project END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'asc' THEN spend END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'desc' THEN spend END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'sessions' AND sqlc.arg(sort_dir)::text = 'asc' THEN sessions END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'sessions' AND sqlc.arg(sort_dir)::text = 'desc' THEN sessions END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'avg_duration' AND sqlc.arg(sort_dir)::text = 'asc' THEN avg_duration END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'projects' AND sqlc.arg(sort_by)::text = 'avg_duration' AND sqlc.arg(sort_dir)::text = 'desc' THEN avg_duration END DESC,
  spend DESC;
