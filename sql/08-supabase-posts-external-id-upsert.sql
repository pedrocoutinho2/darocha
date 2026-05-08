-- ============================================================================
-- SQL 08: EXTERNAL_ID EM POSTS + IMPORT IDEMPOTENTE (UPSERT INTELIGENTE)
-- ============================================================================
-- PROBLEMA RESOLVIDO:
-- A função import_planning original apaga TODOS os posts de um mês via
-- DELETE CASCADE quando p_replace=TRUE. Isso destrói comentários, replies,
-- reactions, mídias e o status de aprovação dos clientes.
--
-- Adicionalmente, a função antiga não validava o campo title (introduzido
-- pelo SQL 07), causando erros de NOT NULL no banco em vez de erro
-- amigável da própria função.
--
-- SOLUÇÃO:
-- - Cada post ganha um external_id (slug-style, único por client_id) que vem
--   no JSON do planejamento.
-- - import_planning vira upsert inteligente baseado em external_id:
--     * UPDATE se post existe (preserva id, status, comments, reactions, mídia)
--     * INSERT se post é novo
--     * DELETE se post foi removido do JSON (com salvaguarda)
-- - Posts existentes (sem external_id) ganham um external_id sintético baseado
--   em date+time, preservando-os.
-- - Validação de title como obrigatório (max 30 chars).
--
-- BLOCO `campaigns` no JSON é IGNORADO silenciosamente nesta versão.
-- TODO: numa versão futura, rejeitar com erro quando reformular tráfego pago.
-- ============================================================================

-- ============================================================================
-- PARTE 1: SCHEMA — adiciona external_id e migra posts existentes
-- ============================================================================

-- 1.1) Coluna external_id nullable inicialmente
ALTER TABLE posts ADD COLUMN IF NOT EXISTS external_id TEXT;

-- 1.2) Gera external_id sintético pros posts existentes que não têm
-- Padrão: "{client-slug}-{date-iso}-{time-sem-separador}"
-- Ex: "telecall-2026-05-04-100000"
UPDATE posts p
SET external_id = c.slug || '-' || to_char(p.date, 'YYYY-MM-DD') || '-' || replace(p.time::TEXT, ':', '')
FROM clients c
WHERE p.client_id = c.id
  AND p.external_id IS NULL;

-- 1.3) Constraint UNIQUE composta (client_id, external_id) — só se ainda não existir
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'posts'::regclass
      AND conname = 'posts_client_external_id_unique'
  ) THEN
    ALTER TABLE posts
      ADD CONSTRAINT posts_client_external_id_unique
      UNIQUE (client_id, external_id);
  END IF;
END $$;

-- 1.4) Tornar NOT NULL (todos os posts já têm external_id depois do UPDATE acima)
ALTER TABLE posts ALTER COLUMN external_id SET NOT NULL;

-- 1.5) CHECK constraint pra garantir formato slug-style (minúsculas, hífen, números)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'posts'::regclass
      AND conname = 'posts_external_id_format'
  ) THEN
    ALTER TABLE posts
      ADD CONSTRAINT posts_external_id_format
      CHECK (external_id ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' OR length(external_id) = 1);
  END IF;
END $$;


-- ============================================================================
-- PARTE 2: NOVA FUNÇÃO import_planning (upsert idempotente)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.import_planning(
  p_payload JSONB, p_replace BOOLEAN DEFAULT FALSE
) RETURNS JSON AS $$
DECLARE
  v_client_slug TEXT;
  v_client_id BIGINT;
  v_month TEXT;
  v_month_start DATE;
  v_month_end DATE;
  v_post JSONB;
  v_user_id UUID;
  v_post_idx INT := 0;
  v_external_id TEXT;
  v_title TEXT;
  v_existing_post_id BIGINT;
  v_inserted_count INT := 0;
  v_updated_count INT := 0;
  v_deleted_count INT := 0;
  v_imported_external_ids TEXT[] := ARRAY[]::TEXT[];
  v_max_deletions INT := 5;
BEGIN
  -- Permissão
  IF NOT public.is_editor_or_admin() THEN
    RAISE EXCEPTION 'Sem permissão pra importar planejamento';
  END IF;
  v_user_id := auth.uid();

  -- Validações básicas do payload
  IF p_payload->>'version' IS NULL OR p_payload->>'version' != '1.0' THEN
    RAISE EXCEPTION 'Versão inválida (esperado 1.0)';
  END IF;
  IF p_payload->>'client_slug' IS NULL THEN
    RAISE EXCEPTION 'client_slug obrigatório';
  END IF;
  IF p_payload->>'month' IS NULL OR (p_payload->>'month') !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'month inválido (formato esperado YYYY-MM)';
  END IF;

  v_client_slug := p_payload->>'client_slug';
  v_month := p_payload->>'month';

  SELECT id INTO v_client_id FROM clients WHERE slug = v_client_slug AND active = TRUE;
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION 'Cliente não encontrado ou inativo: %', v_client_slug;
  END IF;

  v_month_start := (v_month || '-01')::DATE;
  v_month_end := (v_month_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  -- ============================================================================
  -- LOOP DE POSTS: upsert por external_id
  -- ============================================================================
  FOR v_post IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'posts', '[]'::JSONB)) LOOP
    v_post_idx := v_post_idx + 1;

    -- Validação data dentro do mês
    IF (v_post->>'date')::DATE NOT BETWEEN v_month_start AND v_month_end THEN
      RAISE EXCEPTION 'Post %: data % fora do mês %', v_post_idx, v_post->>'date', v_month;
    END IF;

    -- Validação external_id
    v_external_id := v_post->>'external_id';
    IF v_external_id IS NULL OR length(trim(v_external_id)) = 0 THEN
      RAISE EXCEPTION 'Post %: campo external_id é obrigatório', v_post_idx;
    END IF;
    IF v_external_id !~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' AND length(v_external_id) > 1 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): formato inválido. Use minúsculas, números e hífen.', v_post_idx, v_external_id;
    END IF;

    -- Validação title
    v_title := v_post->>'title';
    IF v_title IS NULL OR length(trim(v_title)) = 0 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): campo title é obrigatório', v_post_idx, v_external_id;
    END IF;
    IF length(v_title) > 30 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): title tem % caracteres, máximo 30', v_post_idx, v_external_id, length(v_title);
    END IF;

    -- Detecta duplicação dentro do próprio JSON
    IF v_external_id = ANY(v_imported_external_ids) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): external_id duplicado dentro do JSON', v_post_idx, v_external_id;
    END IF;
    v_imported_external_ids := array_append(v_imported_external_ids, v_external_id);

    -- Procura post existente
    SELECT id INTO v_existing_post_id
    FROM posts
    WHERE client_id = v_client_id AND external_id = v_external_id;

    IF v_existing_post_id IS NOT NULL THEN
      -- UPDATE: preserva id, status, comments, reactions, mídia
      UPDATE posts SET
        date = (v_post->>'date')::DATE,
        time = (v_post->>'time')::TIME,
        title = v_title,
        format = v_post->>'format',
        pillar = v_post->>'pillar',
        instagram = v_post->>'instagram',
        linkedin = v_post->>'linkedin',
        briefing_summary = v_post->>'briefing_summary',
        briefing_full = v_post->'briefing_full'
      WHERE id = v_existing_post_id;
      v_updated_count := v_updated_count + 1;
    ELSE
      -- INSERT: post novo
      INSERT INTO posts (
        client_id, external_id, date, time, title, format, pillar,
        instagram, linkedin, briefing_summary, briefing_full,
        status, created_by
      ) VALUES (
        v_client_id, v_external_id,
        (v_post->>'date')::DATE, (v_post->>'time')::TIME,
        v_title, v_post->>'format', v_post->>'pillar',
        v_post->>'instagram', v_post->>'linkedin',
        v_post->>'briefing_summary', v_post->'briefing_full',
        COALESCE(v_post->>'status', 'pending'),
        v_user_id
      );
      v_inserted_count := v_inserted_count + 1;
    END IF;
  END LOOP;

  -- ============================================================================
  -- DELEÇÃO DE POSTS REMOVIDOS DO JSON (apenas se p_replace=TRUE)
  -- Posts no banco no mês desse cliente que NÃO estão no JSON novo são apagados.
  -- Salvaguarda: se tiver mais que v_max_deletions, retorna erro.
  -- ============================================================================
  IF p_replace THEN
    -- Conta quantos posts seriam deletados
    SELECT COUNT(*) INTO v_deleted_count
    FROM posts
    WHERE client_id = v_client_id
      AND date BETWEEN v_month_start AND v_month_end
      AND NOT (external_id = ANY(v_imported_external_ids));

    IF v_deleted_count > v_max_deletions THEN
      RAISE EXCEPTION 'Salvaguarda ativada: import removeria % posts (máximo permitido: %). Verifique se o JSON está completo. Se realmente quer remover, ajuste a função ou faça em etapas.', v_deleted_count, v_max_deletions;
    END IF;

    -- Pode deletar (CASCADE apaga comments, replies, reactions, mídia desses posts)
    DELETE FROM posts
    WHERE client_id = v_client_id
      AND date BETWEEN v_month_start AND v_month_end
      AND NOT (external_id = ANY(v_imported_external_ids));
  END IF;

  -- ============================================================================
  -- BLOCO campaigns: ignorado silenciosamente nesta versão
  -- TODO: rejeitar com erro quando reformular sistema de tráfego pago
  -- ============================================================================

  -- Histórico de import
  INSERT INTO import_history (
    client_id, month, imported_by,
    posts_count, campaigns_count, ads_count,
    replaced, raw_payload
  ) VALUES (
    v_client_id, v_month, v_user_id,
    v_inserted_count + v_updated_count, 0, 0,
    p_replace AND v_deleted_count > 0,
    p_payload
  );

  RETURN json_build_object(
    'success', true,
    'posts_inserted', v_inserted_count,
    'posts_updated', v_updated_count,
    'posts_deleted', v_deleted_count,
    'message', format('Import concluído: %s novos, %s atualizados, %s removidos.',
                       v_inserted_count, v_updated_count, v_deleted_count)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
