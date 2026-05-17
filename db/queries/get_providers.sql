-- name: GetProviders :many
WITH agg AS (
  SELECT sms.provider, COALESCE(SUM(sms.cost), 0)::float8 as spend, COALESCE(SUM(sms.in_tok+sms.out_tok+sms.cache_tok), 0)::bigint as tokens, COALESCE(SUM(sms.tools), 0)::bigint as tools, COALESCE(SUM(sms.errors), 0)::bigint as errors
  FROM t_session_model_stats_raw sms
  WHERE (sqlc.arg(days)::int = 0 OR EXISTS (SELECT 1 FROM t_sessions s WHERE s.harness = sms.harness AND s.filename = sms.filename AND epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int)))
    AND (sqlc.arg(project)::text = '' OR EXISTS (SELECT 1 FROM t_sessions s WHERE s.harness = sms.harness AND s.filename = sms.filename AND s.project = sqlc.arg(project)))
    AND (sqlc.arg(filename)::text = '' OR sms.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR sms.harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR sms.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR sms.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (SELECT 1 FROM t_unified_events e WHERE e.harness = sms.harness AND e.filename = sms.filename AND e.tool = sqlc.arg(tool)))
  GROUP BY sms.provider
)
SELECT
  provider,
  spend,
  printf('$%.4f', spend)::text as spend_display,
  tokens,
  CASE WHEN tokens < 1000 THEN CAST(tokens AS VARCHAR) WHEN tokens < 1000000 THEN printf('%.1fK', tokens / 1000.0) WHEN tokens < 1000000000 THEN printf('%.1fM', tokens / 1000000.0) ELSE printf('%.1fB', tokens / 1000000000.0) END::text as tokens_display,
  tools,
  errors
FROM agg
ORDER BY
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'provider' AND sqlc.arg(sort_dir)::text = 'asc' THEN provider END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'provider' AND sqlc.arg(sort_dir)::text = 'desc' THEN provider END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'asc' THEN spend END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'spend' AND sqlc.arg(sort_dir)::text = 'desc' THEN spend END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'tokens' AND sqlc.arg(sort_dir)::text = 'asc' THEN tokens END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'tokens' AND sqlc.arg(sort_dir)::text = 'desc' THEN tokens END DESC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'tools' AND sqlc.arg(sort_dir)::text = 'asc' THEN tools END ASC,
  CASE WHEN sqlc.arg(sort_table)::text = 'providers' AND sqlc.arg(sort_by)::text = 'tools' AND sqlc.arg(sort_dir)::text = 'desc' THEN tools END DESC,
  spend DESC;
