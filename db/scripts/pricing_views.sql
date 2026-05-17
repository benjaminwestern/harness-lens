BEGIN TRANSACTION;
CREATE OR REPLACE VIEW api_pricing AS
WITH raw AS (
  SELECT CAST(content AS JSON) as j FROM read_text('https://models.dev/api.json')
),
providers AS (
  SELECT unnest(from_json(json_keys(j), '["VARCHAR"]')) as provider_key, j FROM raw
),
provider_models AS (
  SELECT provider_key, j->provider_key->'models' as models_json FROM providers
),
models AS (
  SELECT provider_key, unnest(from_json(json_keys(models_json), '["VARCHAR"]')) as model_key, models_json
  FROM provider_models WHERE models_json IS NOT NULL
)
SELECT 
  model_key,
  min_by(provider_key, CASE 
    WHEN provider_key IN ('openai','anthropic','google','deepseek','mistral','cohere','xai','togetherai','fireworks-ai','groq') THEN 1
    WHEN provider_key IN ('google-vertex','azure','amazon-bedrock','cloudflare-workers-ai') THEN 2
    ELSE 3
  END) as provider,
  MAX(models_json->model_key->>'name') as friendly_name,
  MAX(CAST(models_json->model_key->'cost'->>'input' AS DOUBLE)) as input_cost,
  MAX(CAST(models_json->model_key->'cost'->>'output' AS DOUBLE)) as output_cost,
  MAX(CAST(models_json->model_key->'cost'->>'cache_read' AS DOUBLE)) as cache_cost,
  MAX(CAST(models_json->model_key->'cost'->>'cache_write' AS DOUBLE)) as cache_write_cost
FROM models GROUP BY model_key;

CREATE OR REPLACE VIEW model_mappings AS
SELECT * FROM (VALUES 
  ('accounts/fireworks/routers/kimi-k2p6-turbo', 'kimi-k2.6'),
  ('accounts/fireworks/models/kimi-k2p6', 'kimi-k2.6')
) t(raw_model, api_model);

CREATE OR REPLACE VIEW v_pricing_map AS
SELECT m.raw_model as model, p.provider, p.friendly_name, p.input_cost, p.output_cost, p.cache_cost, p.cache_write_cost
FROM model_mappings m JOIN api_pricing p ON m.api_model = p.model_key
UNION ALL
SELECT p.model_key as model, p.provider, p.friendly_name, p.input_cost, p.output_cost, p.cache_cost, p.cache_write_cost
FROM api_pricing p
WHERE NOT EXISTS (SELECT 1 FROM model_mappings m WHERE m.raw_model = p.model_key);
COMMIT;
