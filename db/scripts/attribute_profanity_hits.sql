CREATE OR REPLACE TABLE t_profanity_hits_attributed AS
WITH candidates AS (
  SELECT h.hit_id, h.harness, h.filename, h.project, h.ts, h.word, h.group_name, h.severity,
    a.model, a.provider,
    row_number() OVER (PARTITION BY h.hit_id ORDER BY a.ts ASC NULLS LAST) as rn
  FROM t_profanity_hits h
  LEFT JOIN t_unified_events a ON a.harness = h.harness
    AND a.filename = h.filename
    AND a.is_turn = 1
    AND a.ts >= h.ts
    AND a.model IS NOT NULL
    AND a.model != ''
)
SELECT hit_id, harness, filename, project, ts, word, group_name, severity, model, provider
FROM candidates
WHERE rn = 1;
