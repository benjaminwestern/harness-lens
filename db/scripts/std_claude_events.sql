CREATE OR REPLACE VIEW std_claude_events AS
WITH claude_raw AS (
  SELECT CAST(filename AS VARCHAR) as filename, type, timestamp, cwd, sessionId, uuid, parentUuid, sourceToolAssistantUUID, isSidechain, isMeta, message, toolUseResult, usage, costUSD
  FROM read_json('{{sql .Home}}/.claude/projects/**/*.jsonl', format='auto', columns={'type':'VARCHAR', 'timestamp':'VARCHAR', 'cwd':'VARCHAR', 'sessionId':'VARCHAR', 'uuid':'VARCHAR', 'parentUuid':'VARCHAR', 'sourceToolAssistantUUID':'VARCHAR', 'isSidechain':'BOOLEAN', 'isMeta':'BOOLEAN', 'message':'JSON', 'toolUseResult':'JSON', 'usage':'JSON', 'costUSD':'DOUBLE'}, filename=true, ignore_errors=true)
),
claude_norm AS (
  SELECT filename, type, timestamp, cwd, sessionId, uuid, parentUuid, sourceToolAssistantUUID, isSidechain, isMeta, message, toolUseResult, usage, costUSD,
    MAX(cwd) FILTER (WHERE cwd IS NOT NULL) OVER (PARTITION BY filename) as session_cwd
  FROM claude_raw
),
assistant_events AS (
  SELECT 'claude' as harness, filename,
    COALESCE(string_split(session_cwd, '/')[-1], string_split(filename, '/')[-2], 'claude') as project,
    json_extract_string(message, '$.model') as raw_model,
    json_extract_string(message, '$.model') as model,
    'anthropic' as provider,
    session_cwd,
    epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
    COALESCE(costUSD, (
      coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.input_tokens'), json_extract_string(usage, '$.input_tokens')) AS BIGINT), 0) * coalesce(p.input_cost, 0) +
      (coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation_input_tokens'), json_extract_string(usage, '$.cache_creation_input_tokens')) AS BIGINT), 0) +
       coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation.ephemeral_5m_input_tokens'), json_extract_string(usage, '$.cache_creation.ephemeral_5m_input_tokens')) AS BIGINT), 0) +
       coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation.ephemeral_1h_input_tokens'), json_extract_string(usage, '$.cache_creation.ephemeral_1h_input_tokens')) AS BIGINT), 0)) * coalesce(p.cache_write_cost, p.input_cost, 0) +
      coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.output_tokens'), json_extract_string(usage, '$.output_tokens')) AS BIGINT), 0) * coalesce(p.output_cost, 0) +
      coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_read_input_tokens'), json_extract_string(usage, '$.cache_read_input_tokens')) AS BIGINT), 0) * coalesce(p.cache_cost, 0)
    ) / 1000000.0) as cost,
    (coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.input_tokens'), json_extract_string(usage, '$.input_tokens')) AS BIGINT), 0) +
     coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation_input_tokens'), json_extract_string(usage, '$.cache_creation_input_tokens')) AS BIGINT), 0) +
     coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation.ephemeral_5m_input_tokens'), json_extract_string(usage, '$.cache_creation.ephemeral_5m_input_tokens')) AS BIGINT), 0) +
     coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_creation.ephemeral_1h_input_tokens'), json_extract_string(usage, '$.cache_creation.ephemeral_1h_input_tokens')) AS BIGINT), 0)) as in_tok,
    coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.output_tokens'), json_extract_string(usage, '$.output_tokens')) AS BIGINT), 0) as out_tok,
    coalesce(try_cast(COALESCE(json_extract_string(message, '$.usage.cache_read_input_tokens'), json_extract_string(usage, '$.cache_read_input_tokens')) AS BIGINT), 0) as cache_tok,
    1 as is_turn,
    0 as is_user,
    0 as is_tool,
    0 as is_error,
    CAST(NULL AS VARCHAR) as tool
  FROM claude_norm
  LEFT JOIN v_pricing_map p ON p.model = json_extract_string(message, '$.model')
  WHERE type = 'assistant' AND json_extract_string(message, '$.role') = 'assistant'
),
user_events AS (
  SELECT 'claude' as harness, filename,
    COALESCE(string_split(session_cwd, '/')[-1], string_split(filename, '/')[-2], 'claude') as project,
    CAST(NULL AS VARCHAR) as raw_model,
    CAST(NULL AS VARCHAR) as model,
    'anthropic' as provider,
    session_cwd,
    epoch_ms(try_cast(timestamp AS TIMESTAMP)) as ts,
    0.0 as cost,
    0 as in_tok,
    0 as out_tok,
    0 as cache_tok,
    0 as is_turn,
    1 as is_user,
    0 as is_tool,
    0 as is_error,
    CAST(NULL AS VARCHAR) as tool
  FROM claude_norm
  WHERE type = 'user'
    AND NOT coalesce(isMeta, false)
    AND NOT (json_type(json_extract(message, '$.content')) = 'ARRAY' AND CAST(json_extract(message, '$.content') AS VARCHAR) LIKE '%"tool_result"%')
),
content_items AS (
  SELECT filename, type, timestamp, session_cwd, uuid as message_uuid, parentUuid, sourceToolAssistantUUID, message, toolUseResult,
    unnest(from_json(CAST(json_extract(message, '$.content') AS VARCHAR), '["JSON"]')) as item
  FROM claude_norm
  WHERE json_type(json_extract(message, '$.content')) = 'ARRAY'
),
tool_uses AS (
  SELECT filename,
    message_uuid as assistant_uuid,
    json_extract_string(item, '$.id') as tool_use_id,
    COALESCE(json_extract_string(item, '$.name'), json_extract_string(item, '$.type'), 'tool') as tool,
    json_extract_string(message, '$.model') as raw_model,
    json_extract_string(message, '$.model') as model,
    session_cwd,
    timestamp
  FROM content_items
  LEFT JOIN v_pricing_map p ON p.model = json_extract_string(message, '$.model')
  WHERE type = 'assistant'
    AND (json_extract_string(item, '$.type') = 'tool_use' OR json_extract_string(item, '$.type') LIKE '%_tool_use')
),
tool_results AS (
  SELECT filename,
    json_extract_string(item, '$.tool_use_id') as tool_use_id,
    COALESCE(sourceToolAssistantUUID, parentUuid) as assistant_uuid,
    CASE WHEN coalesce(try_cast(json_extract_string(item, '$.is_error') AS BOOLEAN), false) THEN 1 ELSE 0 END as is_error
  FROM content_items
  WHERE type = 'user'
    AND (json_extract_string(item, '$.type') = 'tool_result' OR json_extract_string(item, '$.type') LIKE '%_tool_result')
  UNION ALL
  SELECT filename,
    json_extract_string(toolUseResult, '$.tool_use_id') as tool_use_id,
    COALESCE(sourceToolAssistantUUID, parentUuid) as assistant_uuid,
    CASE WHEN coalesce(try_cast(json_extract_string(toolUseResult, '$.is_error') AS BOOLEAN), false) THEN 1 ELSE 0 END as is_error
  FROM claude_norm
  WHERE type = 'user' AND toolUseResult IS NOT NULL
),
tool_result_errors AS (
  SELECT filename, tool_use_id, assistant_uuid, max(is_error) as is_error
  FROM tool_results
  GROUP BY filename, tool_use_id, assistant_uuid
),
tool_events AS (
  SELECT 'claude' as harness, tu.filename,
    COALESCE(string_split(tu.session_cwd, '/')[-1], string_split(tu.filename, '/')[-2], 'claude') as project,
    tu.raw_model,
    tu.model,
    'anthropic' as provider,
    tu.session_cwd,
    epoch_ms(try_cast(tu.timestamp AS TIMESTAMP)) as ts,
    0.0 as cost,
    0 as in_tok,
    0 as out_tok,
    0 as cache_tok,
    0 as is_turn,
    0 as is_user,
    1 as is_tool,
    coalesce(max(tre.is_error), 0) as is_error,
    tu.tool
  FROM tool_uses tu
  LEFT JOIN tool_result_errors tre ON tre.filename = tu.filename AND (
    (tre.tool_use_id IS NOT NULL AND tre.tool_use_id = tu.tool_use_id) OR
    (tre.assistant_uuid IS NOT NULL AND tre.assistant_uuid = tu.assistant_uuid)
  )
  GROUP BY tu.filename, tu.session_cwd, tu.timestamp, tu.raw_model, tu.model, tu.tool, tu.tool_use_id, tu.assistant_uuid
)
SELECT * FROM assistant_events
UNION ALL
SELECT * FROM user_events
UNION ALL
SELECT * FROM tool_events;
