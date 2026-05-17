-- name: GetSessionProfanity :many
WITH filtered AS (
  SELECT h.*
  FROM t_profanity_hits_attributed h
  WHERE h.harness = sqlc.arg(harness)
    AND h.filename = sqlc.arg(filename)
),
agg AS (
  SELECT
    group_name,
    any_value(severity)::text as severity,
    COUNT(*)::bigint as count,
    COUNT(*) FILTER (WHERE severity = 'strong')::bigint as strong_count,
    COUNT(*) FILTER (WHERE severity = 'moderate')::bigint as moderate_count,
    COUNT(*) FILTER (WHERE severity = 'mild')::bigint as mild_count,
    string_agg(DISTINCT word, ', ' ORDER BY word)::text as words
  FROM filtered
  GROUP BY group_name
),
scored AS (
  SELECT
    group_name,
    severity,
    count,
    strong_count,
    moderate_count,
    mild_count,
    words,
    SUM(count) OVER ()::bigint as total_hits,
    SUM((CASE severity WHEN 'strong' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END) * count) OVER ()::bigint as feel_score
  FROM agg
)
SELECT
  group_name,
  severity,
  count,
  strong_count,
  moderate_count,
  mild_count,
  words,
  total_hits,
  feel_score,
  CASE
    WHEN feel_score = 0 THEN 'calm'
    WHEN feel_score <= 3 THEN 'irked'
    WHEN feel_score <= 9 THEN 'frustrated'
    ELSE 'furious'
  END::text as feel_display
FROM scored
ORDER BY count DESC, group_name
LIMIT 20;
