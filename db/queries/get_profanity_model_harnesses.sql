-- name: GetProfanityModelHarnesses :many
WITH filtered_hits AS (
  SELECT
    h.harness,
    h.filename,
    COALESCE(h.model, 'unknown')::text as model,
    COALESCE(h.provider, 'unknown')::text as provider,
    h.severity,
    s.user_turns
  FROM t_profanity_hits_attributed h
  JOIN t_sessions s ON s.harness = h.harness AND s.filename = h.filename
  WHERE (sqlc.arg(days)::int = 0 OR epoch_ms(s.start_time) >= current_date - to_days(sqlc.arg(days)::int))
    AND (sqlc.arg(project)::text = '' OR s.project = sqlc.arg(project))
    AND (sqlc.arg(filename)::text = '' OR h.filename = sqlc.arg(filename))
    AND (sqlc.arg(harness)::text = '' OR h.harness = sqlc.arg(harness))
    AND (sqlc.arg(provider)::text = '' OR h.provider = sqlc.arg(provider))
    AND (sqlc.arg(model)::text = '' OR h.model = sqlc.arg(model))
    AND (sqlc.arg(tool)::text = '' OR EXISTS (
      SELECT 1 FROM t_model_tools mt
      WHERE mt.harness = h.harness
        AND mt.filename = h.filename
        AND mt.tool = sqlc.arg(tool)
        AND (h.model IS NULL OR mt.model = h.model)
        AND (h.provider IS NULL OR mt.provider IS NOT DISTINCT FROM h.provider)
    ))
),
hit_agg AS (
  SELECT
    harness,
    model,
    provider,
    COUNT(*)::bigint as count,
    COUNT(*) FILTER (WHERE severity = 'strong')::bigint as strong_count,
    COUNT(*) FILTER (WHERE severity = 'moderate')::bigint as moderate_count,
    COUNT(*) FILTER (WHERE severity = 'mild')::bigint as mild_count,
    COALESCE(SUM(CASE severity WHEN 'strong' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END), 0)::bigint as feel_score,
    COUNT(DISTINCT harness || ':' || filename)::bigint as sessions
  FROM filtered_hits
  GROUP BY harness, model, provider
),
turn_agg AS (
  SELECT harness, model, provider, COALESCE(SUM(user_turns), 0)::bigint as user_turns
  FROM (SELECT DISTINCT harness, filename, model, provider, user_turns FROM filtered_hits)
  GROUP BY harness, model, provider
)
SELECT
  h.harness,
  h.model,
  h.provider,
  h.count,
  h.strong_count,
  h.moderate_count,
  h.mild_count,
  h.feel_score,
  CASE WHEN h.feel_score = 0 THEN 'calm' WHEN h.feel_score <= 3 THEN 'irked' WHEN h.feel_score <= 9 THEN 'frustrated' ELSE 'furious' END::text as feel_display,
  h.sessions,
  COALESCE(t.user_turns, 0)::bigint as user_turns,
  CASE WHEN COALESCE(t.user_turns, 0) = 0 THEN '0.00' ELSE printf('%.2f', h.count * 1.0 / t.user_turns) END::text as swears_per_user_turn_display
FROM hit_agg h
LEFT JOIN turn_agg t ON t.harness = h.harness AND t.model = h.model AND t.provider = h.provider
ORDER BY
  h.count DESC,
  h.feel_score DESC,
  h.harness ASC,
  h.model ASC;
