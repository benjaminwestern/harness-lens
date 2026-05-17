-- name: GetTimeline :many
WITH filtered_sessions AS (
  SELECT harness, filename, start_time, project
  FROM t_sessions
  WHERE start_time > 0
    AND (sqlc.arg(days)::int = 0 OR epoch_ms(start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR harness = sqlc.arg(harness))
),
usage_daily AS (
  SELECT
    CAST(CAST(to_timestamp(s.start_time/1000) AS TIMESTAMP) AS DATE)::varchar as date,
    COALESCE(SUM(sms.cost), 0)::float8 as spend,
    COALESCE(SUM(sms.in_tok + sms.out_tok + sms.cache_tok), 0)::bigint as tokens
  FROM t_session_model_stats_raw sms
  JOIN filtered_sessions s ON s.harness = sms.harness AND s.filename = sms.filename
  WHERE (sqlc.arg(provider)::text = '' OR sms.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR sms.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (
      SELECT 1
      FROM t_model_tools mt
      WHERE mt.harness = sms.harness
        AND mt.filename = sms.filename
        AND mt.model = sms.model
        AND mt.provider IS NOT DISTINCT FROM sms.provider
        AND mt.tool = sqlc.arg(tool)
    ))
  GROUP BY date
),
tool_daily AS (
  SELECT
    CAST(CAST(to_timestamp(s.start_time/1000) AS TIMESTAMP) AS DATE)::varchar as date,
    COALESCE(SUM(mt.count), 0)::bigint as tool_calls,
    COALESCE(SUM(mt.errors), 0)::bigint as tool_errors
  FROM t_model_tools mt
  JOIN filtered_sessions s ON s.harness = mt.harness AND s.filename = mt.filename
  WHERE (sqlc.arg(provider)::text = '' OR mt.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR mt.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR mt.tool = sqlc.arg(tool))
  GROUP BY date
),
profanity_daily AS (
  SELECT
    CAST(CAST(to_timestamp(s.start_time/1000) AS TIMESTAMP) AS DATE)::varchar as date,
    COUNT(*)::bigint as profanity_hits,
    COALESCE(SUM(CASE h.severity WHEN 'strong' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END), 0)::bigint as feel_score
  FROM t_profanity_hits_attributed h
  JOIN filtered_sessions s ON s.harness = h.harness AND s.filename = h.filename
  WHERE (sqlc.arg(provider)::text = '' OR h.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR h.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (
      SELECT 1
      FROM t_model_tools mt
      WHERE mt.harness = h.harness
        AND mt.filename = h.filename
        AND mt.tool = sqlc.arg(tool)
        AND (h.model IS NULL OR mt.model = h.model)
        AND (h.provider IS NULL OR mt.provider IS NOT DISTINCT FROM h.provider)
    ))
  GROUP BY date
),
all_dates AS (
  SELECT date FROM usage_daily
  UNION
  SELECT date FROM tool_daily
  UNION
  SELECT date FROM profanity_daily
),
agg AS (
  SELECT
    d.date,
    COALESCE(u.spend, 0)::float8 as spend,
    COALESCE(u.tokens, 0)::bigint as tokens,
    COALESCE(t.tool_calls, 0)::bigint as tool_calls,
    COALESCE(t.tool_errors, 0)::bigint as tool_errors,
    COALESCE(p.profanity_hits, 0)::bigint as profanity_hits,
    COALESCE(p.feel_score, 0)::bigint as feel_score
  FROM all_dates d
  LEFT JOIN usage_daily u ON u.date = d.date
  LEFT JOIN tool_daily t ON t.date = d.date
  LEFT JOIN profanity_daily p ON p.date = d.date
)
SELECT
  date,
  spend as cost,
  printf('$%.2f', spend)::text as cost_display,
  tokens,
  CASE WHEN tokens < 1000 THEN CAST(tokens AS VARCHAR) WHEN tokens < 1000000 THEN printf('%.1fK', tokens / 1000.0) WHEN tokens < 1000000000 THEN printf('%.1fM', tokens / 1000000.0) ELSE printf('%.1fB', tokens / 1000000000.0) END::text as tokens_display,
  tool_calls,
  CASE WHEN tool_calls < 1000 THEN CAST(tool_calls AS VARCHAR) WHEN tool_calls < 1000000 THEN printf('%.1fK', tool_calls / 1000.0) ELSE printf('%.1fM', tool_calls / 1000000.0) END::text as tool_calls_display,
  tool_errors,
  CASE WHEN tool_errors < 1000 THEN CAST(tool_errors AS VARCHAR) WHEN tool_errors < 1000000 THEN printf('%.1fK', tool_errors / 1000.0) ELSE printf('%.1fM', tool_errors / 1000000.0) END::text as tool_errors_display,
  profanity_hits,
  CASE WHEN profanity_hits < 1000 THEN CAST(profanity_hits AS VARCHAR) WHEN profanity_hits < 1000000 THEN printf('%.1fK', profanity_hits / 1000.0) ELSE printf('%.1fM', profanity_hits / 1000000.0) END::text as profanity_hits_display,
  feel_score,
  CASE WHEN feel_score = 0 THEN 'calm' WHEN feel_score <= 3 THEN 'irked' WHEN feel_score <= 9 THEN 'frustrated' ELSE 'furious' END::text as feel_display
FROM agg
ORDER BY date;
