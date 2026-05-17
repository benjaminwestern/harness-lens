BEGIN TRANSACTION;
CREATE OR REPLACE VIEW v_session_model_stats_raw AS
WITH model_keys AS (
  SELECT DISTINCT harness, filename, model, provider
  FROM t_unified_events
  WHERE model IS NOT NULL AND model != ''
    AND (is_turn = 1 OR cost != 0 OR (in_tok + out_tok + cache_tok) > 0)
),
usage_agg AS (
  SELECT harness, filename, model, provider,
    any_value(raw_model) FILTER (WHERE raw_model IS NOT NULL AND raw_model != '') as raw_model,
    SUM(cost) as cost,
    SUM(in_tok) as in_tok,
    SUM(out_tok) as out_tok,
    SUM(cache_tok) as cache_tok
  FROM t_unified_events
  WHERE model IS NOT NULL AND model != ''
    AND (cost != 0 OR (in_tok + out_tok + cache_tok) > 0)
  GROUP BY harness, filename, model, provider
),
assistant_turns AS (
  SELECT harness, filename, ts as asst_ts, raw_model, model, provider,
    lead(ts) OVER (PARTITION BY harness, filename ORDER BY ts) as next_asst_ts
  FROM t_unified_events
  WHERE is_turn = 1 AND model IS NOT NULL AND model != ''
),
turn_agg AS (
  SELECT harness, filename, model, provider,
    any_value(raw_model) FILTER (WHERE raw_model IS NOT NULL AND raw_model != '') as raw_model,
    COUNT(*) as turns
  FROM assistant_turns
  GROUP BY harness, filename, model, provider
),
tool_results AS (
  SELECT harness, filename, ts, tool, is_error FROM t_unified_events WHERE is_tool = 1 AND tool IS NOT NULL
),
tool_agg AS (
  SELECT a.harness, a.filename, a.model, a.provider,
    COUNT(t.tool) as tools,
    COUNT(*) FILTER (WHERE t.is_error = 1) as errors
  FROM assistant_turns a
  LEFT JOIN tool_results t ON t.harness = a.harness AND t.filename = a.filename AND t.ts >= a.asst_ts AND (t.ts < a.next_asst_ts OR a.next_asst_ts IS NULL)
  GROUP BY a.harness, a.filename, a.model, a.provider
)
SELECT k.harness, k.filename, COALESCE(u.raw_model, ta.raw_model) as raw_model, k.model, k.provider,
  COALESCE(ta.turns, 0)::BIGINT as turns,
  COALESCE(u.cost, 0)::DOUBLE as cost,
  COALESCE(u.in_tok, 0)::BIGINT as in_tok,
  COALESCE(u.out_tok, 0)::BIGINT as out_tok,
  COALESCE(u.cache_tok, 0)::BIGINT as cache_tok,
  COALESCE(tools.tools, 0)::BIGINT as tools,
  COALESCE(tools.errors, 0)::BIGINT as errors
FROM model_keys k
LEFT JOIN usage_agg u ON u.harness = k.harness AND u.filename = k.filename AND u.model = k.model AND u.provider IS NOT DISTINCT FROM k.provider
LEFT JOIN turn_agg ta ON ta.harness = k.harness AND ta.filename = k.filename AND ta.model = k.model AND ta.provider IS NOT DISTINCT FROM k.provider
LEFT JOIN tool_agg tools ON tools.harness = k.harness AND tools.filename = k.filename AND tools.model = k.model AND tools.provider IS NOT DISTINCT FROM k.provider;

CREATE OR REPLACE VIEW v_model_tools AS
SELECT t.harness, t.filename, a.model as model, a.provider as provider,
  t.tool as tool, count(*) as count, count(*) FILTER (WHERE t.is_error = 1) as errors
FROM (SELECT harness, filename, ts, tool, is_error FROM t_unified_events WHERE is_tool = 1 AND tool IS NOT NULL) t
JOIN (
  SELECT harness, filename, ts as asst_ts, model, provider, lead(ts) OVER (PARTITION BY harness, filename ORDER BY ts) as next_asst_ts
  FROM t_unified_events WHERE is_turn = 1 AND model IS NOT NULL AND model != ''
) a
  ON t.harness = a.harness AND t.filename = a.filename AND t.ts >= a.asst_ts AND (t.ts < a.next_asst_ts OR a.next_asst_ts IS NULL)
GROUP BY t.harness, t.filename, a.model, a.provider, t.tool;

CREATE OR REPLACE VIEW v_sessions AS
WITH session_messages AS (
  SELECT harness, filename, min(ts) FILTER (WHERE ts IS NOT NULL AND ts > 0) as start_time, max(ts) FILTER (WHERE ts IS NOT NULL AND ts > 0) as end_time, ANY_VALUE(project) as project,
    list(DISTINCT model) FILTER (WHERE model IS NOT NULL) as models,
    SUM(cost) as cost, SUM(in_tok) as in_tok, SUM(out_tok) as out_tok, SUM(cache_tok) as cache_tok,
    COUNT(*) FILTER (WHERE is_user = 1) as user_turns, COUNT(*) FILTER (WHERE is_turn = 1) as agent_turns,
    COUNT(*) FILTER (WHERE is_tool = 1) as tool_count, COUNT(*) FILTER (WHERE is_error = 1) as tool_error_count
  FROM t_unified_events GROUP BY harness, filename
),
session_meta AS (
  SELECT harness, filename, MAX(session_cwd) as cwd FROM t_unified_events WHERE session_cwd IS NOT NULL GROUP BY harness, filename
),
session_tools AS (
  SELECT harness, filename, sum(count) as tool_count, sum(error_count) as tool_error_count,
    json_group_object(name, count) as tool_breakdown, json_group_object(name, error_count) as tool_error_breakdown
  FROM (SELECT harness, filename, tool as name, count(*) as count, count(*) FILTER (WHERE is_error = 1) as error_count FROM t_unified_events WHERE tool IS NOT NULL GROUP BY harness, filename, tool)
  GROUP BY harness, filename
),
session_model_tools AS (
  SELECT harness, filename, json_group_array(json_object('model', model, 'tool', tool, 'count', count::BIGINT, 'errors', errors::BIGINT, 'error_pct', CASE WHEN count = 0 THEN '0%' ELSE printf('%.1f%%', errors * 100.0 / count) END)) as model_tool_breakdown
  FROM v_model_tools
  GROUP BY harness, filename
),
session_model_stats AS (
  SELECT harness, filename, json_group_array(json_object(
    'model', model,
    'provider', provider,
    'turns', turns::BIGINT,
    'cost', cost::DOUBLE,
    'in_tok', in_tok::BIGINT,
    'out_tok', out_tok::BIGINT,
    'cache_tok', cache_tok::BIGINT,
    'tools', tools::BIGINT,
    'errors', errors::BIGINT,
    'cost_display', printf('$%.4f', cost),
    'token_breakdown_display',
      CASE WHEN in_tok < 1000 THEN CAST(in_tok AS VARCHAR) WHEN in_tok < 1000000 THEN printf('%.1fK', in_tok / 1000.0) WHEN in_tok < 1000000000 THEN printf('%.1fM', in_tok / 1000000.0) ELSE printf('%.1fB', in_tok / 1000000000.0) END || ' in / ' ||
      CASE WHEN out_tok < 1000 THEN CAST(out_tok AS VARCHAR) WHEN out_tok < 1000000 THEN printf('%.1fK', out_tok / 1000.0) WHEN out_tok < 1000000000 THEN printf('%.1fM', out_tok / 1000000.0) ELSE printf('%.1fB', out_tok / 1000000000.0) END || ' out / ' ||
      CASE WHEN cache_tok < 1000 THEN CAST(cache_tok AS VARCHAR) WHEN cache_tok < 1000000 THEN printf('%.1fK', cache_tok / 1000.0) WHEN cache_tok < 1000000000 THEN printf('%.1fM', cache_tok / 1000000.0) ELSE printf('%.1fB', cache_tok / 1000000000.0) END || ' cache',
    'error_pct', CASE WHEN tools = 0 THEN '0%' ELSE printf('%.1f%%', errors * 100.0 / tools) END,
    'cost_per_turn_display', CASE WHEN turns = 0 THEN '$0.0000' ELSE printf('$%.4f', cost / turns) END,
    'cost_per_tool_display', CASE WHEN tools = 0 THEN '$0.0000' ELSE printf('$%.4f', cost / tools) END
  )) as model_stats
  FROM v_session_model_stats_raw GROUP BY harness, filename
)
SELECT m.harness, m.filename, m.start_time, m.end_time, ((m.end_time - m.start_time) / 1000) as duration_sec, m.project, sm.cwd, m.models, m.cost, m.in_tok, m.out_tok, m.cache_tok,
  coalesce(m.user_turns, 0) as user_turns, coalesce(m.agent_turns, 0) as agent_turns, coalesce(m.tool_error_count, 0) as errors, coalesce(t.tool_count, 0) as tool_count, coalesce(t.tool_error_count, 0) as tool_error_count,
  coalesce(t.tool_breakdown, '{}') as tool_breakdown, coalesce(t.tool_error_breakdown, '{}') as tool_error_breakdown, coalesce(smt.model_tool_breakdown, '[]') as model_tool_breakdown, coalesce(sms.model_stats, '[]') as model_stats
FROM session_messages m
LEFT JOIN session_meta sm ON m.harness = sm.harness AND m.filename = sm.filename
LEFT JOIN session_tools t ON m.harness = t.harness AND m.filename = t.filename
LEFT JOIN session_model_tools smt ON m.harness = smt.harness AND m.filename = smt.filename
LEFT JOIN session_model_stats sms ON m.harness = sms.harness AND m.filename = sms.filename
WHERE m.start_time IS NOT NULL;
COMMIT;
