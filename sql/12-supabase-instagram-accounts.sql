-- ============================================================================
-- SQL 12: MAPEAMENTO CLIENTE → CONTA INSTAGRAM (META GRAPH API — P1)
-- ============================================================================
-- CONTEXTO:
-- Integração Meta Graph API para publicação no Instagram (ver
-- docs/META-GRAPH-API.md). O P1 (validação manual) confirmou o fluxo
-- container → media_publish. Para o P2 (Edge Function publish-instagram) o
-- backend precisa saber, para cada cliente, qual é o ig-user-id de destino.
--
-- Esta migração adiciona a coluna `clients.ig_user_id` e faz o seed dos 4
-- ids já validados no P1 (Telecall, CNA Taquara, CNA Queimados, JR Hotéis).
--
-- OBSERVAÇÕES:
-- - ig_user_id é o "Instagram user id" da Graph API (numérico, guardado como
--   text pra evitar qualquer perda de precisão/overflow de bigint).
-- - Nenhum token ou credencial vive no banco: o System User token fica nos
--   secrets do Supabase (definido no P2). Aqui só o id público da conta.
-- - Idempotente: coluna com IF NOT EXISTS, seed via UPDATE por slug.
-- ============================================================================

-- ============================================================================
-- BLOCO 1: COLUNA
-- ============================================================================
ALTER TABLE clients ADD COLUMN IF NOT EXISTS ig_user_id text;

-- ============================================================================
-- BLOCO 2: SEED (ids validados no P1 — ver docs/META-GRAPH-API.md)
-- ============================================================================
UPDATE clients SET ig_user_id = '17841407987295125' WHERE slug = 'telecall';
UPDATE clients SET ig_user_id = '17841416803645638' WHERE slug = 'cna-taquara';
UPDATE clients SET ig_user_id = '17841418328114858' WHERE slug = 'cna-queimados';
UPDATE clients SET ig_user_id = '17841423248731728' WHERE slug = 'jr-hoteis';

-- ============================================================================
-- BLOCO 3: VERIFICAÇÃO (rodar após o seed)
-- ============================================================================
-- SELECT slug, name, ig_user_id FROM clients ORDER BY slug;

-- ============================================================================
-- ROLLBACK (comentado — rodar manualmente se precisar reverter)
-- ============================================================================
-- Opção A: apenas limpar o seed, mantendo a coluna
-- UPDATE clients SET ig_user_id = NULL
--   WHERE slug IN ('telecall', 'cna-taquara', 'cna-queimados', 'jr-hoteis');
--
-- Opção B: remover a coluna por completo
-- ALTER TABLE clients DROP COLUMN IF EXISTS ig_user_id;
-- ============================================================================
