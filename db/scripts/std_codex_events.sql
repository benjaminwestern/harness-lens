CREATE OR REPLACE VIEW std_codex_events AS
WITH codex_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, timestamp, type, payload
  FROM read_json('{{sql .Home}}/.codex/sessions/**/*.jsonl', format='auto', columns={'timestamp':'VARCHAR', 'type':'VARCHAR', 'payload':'JSON'}, filename=true, ignore_errors=true)
),
codex_norm AS (
  SELECT filename, timestamp, type, payload,
    MAX(json_extract_string(payload, '$.cwd')) FILTER (WHERE type = 'session_meta') OVER (PARTITION BY filename) as cwd,
    MAX(json_extract_string(payload, '$.model_provider')) FILTER (WHERE type = 'session_meta') OVER (PARTITION BY filename) as model_provider,
    MAX(json_extract_string(payload, '$.model')) FILTER (WHERE type = 'turn_context') OVER (PARTITION BY filename) as session_model
  FROM codex_raw
),
codex_messages AS (
  SELECT 'codex' as harness, filename,
    COALESCE(string_split(cwd, '/')[-1], 'codex') as project,
    session_model as raw_model,
    session_model as model,
    COALESCE(model_provider, p.provider, 'codex') as provider,
    cwd as session_cwd,
    epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
    0.0 as cost, 0 as in_tok, 0 as out_tok, 0 as cache_tok,
    CASE WHEN type = 'response_item' AND json_extract_string(payload, '$.type') = 'message' AND json_extract_string(payload, '$.role') = 'assistant' THEN 1 ELSE 0 END as is_turn,
    CASE WHEN type = 'response_item' AND json_extract_string(payload, '$.type') = 'message' AND json_extract_string(payload, '$.role') = 'user' THEN 1 ELSE 0 END as is_user,
    0 as is_tool,
    0 as is_error,
    CAST(NULL AS VARCHAR) as tool
  FROM codex_norm
  LEFT JOIN v_pricing_map p ON p.model = session_model
  WHERE type IN ('session_meta', 'response_item')
),
codex_usage AS (
  SELECT 'codex' as harness, filename,
    COALESCE(string_split(cwd, '/')[-1], 'codex') as project,
    session_model as raw_model,
    session_model as model,
    COALESCE(model_provider, p.provider, 'codex') as provider,
    cwd as session_cwd,
    epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
    (
      greatest(coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.input_tokens') AS BIGINT), 0) - coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.cached_input_tokens') AS BIGINT), 0), 0) * coalesce(p.input_cost, 0) +
      coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.output_tokens') AS BIGINT), 0) * coalesce(p.output_cost, 0) +
      coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.cached_input_tokens') AS BIGINT), 0) * coalesce(p.cache_cost, 0)
    ) / 1000000.0 as cost,
    greatest(coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.input_tokens') AS BIGINT), 0) - coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.cached_input_tokens') AS BIGINT), 0), 0) as in_tok,
    coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.output_tokens') AS BIGINT), 0) as out_tok,
    coalesce(try_cast(json_extract_string(payload, '$.info.last_token_usage.cached_input_tokens') AS BIGINT), 0) as cache_tok,
    0 as is_turn,
    0 as is_user,
    0 as is_tool,
    0 as is_error,
    CAST(NULL AS VARCHAR) as tool
  FROM codex_norm
  LEFT JOIN v_pricing_map p ON p.model = session_model
  WHERE type = 'event_msg' AND json_extract_string(payload, '$.type') = 'token_count' AND json_extract(payload, '$.info.last_token_usage') IS NOT NULL
)
SELECT * FROM codex_messages
UNION ALL
SELECT * FROM codex_usage;
