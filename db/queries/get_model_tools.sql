-- name: GetModelTools :many
WITH agg AS (
  SELECT mt.model, COALESCE(mt.provider, 'unknown')::text as provider, mt.tool, COALESCE(SUM(mt.count), 0)::bigint as count, COALESCE(SUM(mt.errors), 0)::bigint as errors
  FROM t_model_tools mt
  WHERE mt.tool IS NOT NULL AND mt.model IS NOT NULL
    AND (sqlc.arg(days)::int = 0 OR EXISTS (SELECT 1 FROM t_sessions s WHERE s.harness = mt.harness AND s.filename = mt.filename AND epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int)))
    AND (sqlc.arg(project)::text = '' OR EXISTS (SELECT 1 FROM t_sessions s WHERE s.harness = mt.harness AND s.filename = mt.filename AND s.project = sqlc.arg(project)))
    AND (sqlc.arg(filename)::text = '' OR mt.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR mt.harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR mt.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR mt.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR mt.tool = sqlc.arg(tool))
  GROUP BY mt.model, mt.provider, mt.tool
)
SELECT model, provider, tool, count, errors, CASE WHEN count = 0 THEN '0%' ELSE printf('%.1f%%', errors * 100.0 / count) END::text as error_pct FROM agg
ORDER BY
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'model' AND sqlc.arg(sort_dir)::text = 'asc' THEN model END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'model' AND sqlc.arg(sort_dir)::text = 'desc' THEN model END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'provider' AND sqlc.arg(sort_dir)::text = 'asc' THEN provider END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'provider' AND sqlc.arg(sort_dir)::text = 'desc' THEN provider END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'tool' AND sqlc.arg(sort_dir)::text = 'asc' THEN tool END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'tool' AND sqlc.arg(sort_dir)::text = 'desc' THEN tool END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'count' AND sqlc.arg(sort_dir)::text = 'asc' THEN count END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'count' AND sqlc.arg(sort_dir)::text = 'desc' THEN count END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'errors' AND sqlc.arg(sort_dir)::text = 'asc' THEN errors END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'model_tools' AND sqlc.arg(sort_by)::text = 'errors' AND sqlc.arg(sort_dir)::text = 'desc' THEN errors END DESC,
  count DESC;
