-- name: GetProfanityGroups :many
WITH filtered_hits AS (
  SELECT h.*
  FROM t_profanity_hits_attributed h
  JOIN t_sessions s ON s.harness = h.harness AND s.filename = h.filename
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR s.project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR s.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR h.harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR h.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR h.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_model_tools mt WHERE mt.harness = h.harness AND mt.filename = h.filename AND mt.tool = sqlc.arg(tool)))
),
agg AS (
  SELECT group_name, any_value(severity)::text as severity, COUNT(*)::bigint as count
  FROM filtered_hits
  GROUP BY group_name
)
SELECT group_name, severity, count FROM agg
ORDER BY count DESC, group_name
LIMIT 20;
