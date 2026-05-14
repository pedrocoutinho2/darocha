-- ============================================================================
-- SQL 09: PLATAFORMAS CONFIGURÁVEIS POR CLIENTE
-- ============================================================================
-- Telecall e JR Hotéis publicam em Instagram + LinkedIn.
-- CNA Taquara e CNA Queimados publicam em Instagram + TikTok.
--
-- Implementação:
-- - Coluna clients.platforms (TEXT[]) define quais plataformas o cliente usa
-- - Coluna posts.tiktok (TEXT, nullable) armazena copy do TikTok
-- - import_planning valida que JSON só traz plataformas habilitadas do cliente
-- ============================================================================

-- ============================================================================
-- PARTE 1: SCHEMA
-- ============================================================================

-- 1.1) Adiciona coluna platforms em clients
ALTER TABLE clients ADD COLUMN IF NOT EXISTS platforms TEXT[] DEFAULT ARRAY['instagram', 'linkedin'];

-- 1.2) Configura plataformas pra cada cliente existente
UPDATE clients SET platforms = ARRAY['instagram', 'linkedin'] WHERE slug = 'telecall';
UPDATE clients SET platforms = ARRAY['instagram', 'tiktok']  WHERE slug = 'cna-taquara';
UPDATE clients SET platforms = ARRAY['instagram', 'tiktok']  WHERE slug = 'cna-queimados';
UPDATE clients SET platforms = ARRAY['instagram', 'linkedin'] WHERE slug = 'jr-hoteis';

-- 1.3) Torna platforms NOT NULL e adiciona CHECK
ALTER TABLE clients ALTER COLUMN platforms SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'clients'::regclass
      AND conname = 'clients_platforms_valid'
  ) THEN
    ALTER TABLE clients
      ADD CONSTRAINT clients_platforms_valid
      CHECK (
        array_length(platforms, 1) >= 1
        AND platforms <@ ARRAY['instagram', 'linkedin', 'tiktok', 'facebook', 'threads', 'youtube']
      );
  END IF;
END $$;

-- 1.4) Adiciona coluna tiktok em posts (nullable)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS tiktok TEXT;

-- ============================================================================
-- PARTE 2: import_planning VALIDA PLATAFORMAS POR CLIENTE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.import_planning(
  p_payload JSONB, p_replace BOOLEAN DEFAULT FALSE
) RETURNS JSON AS $$
DECLARE
  v_client_slug TEXT;
  v_client_id BIGINT;
  v_client_platforms TEXT[];
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
  v_post_has_instagram BOOLEAN;
  v_post_has_linkedin BOOLEAN;
  v_post_has_tiktok BOOLEAN;
BEGIN
  IF NOT public.is_editor_or_admin() THEN
    RAISE EXCEPTION 'Sem permissão pra importar planejamento';
  END IF;
  v_user_id := auth.uid();

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

  SELECT id, platforms INTO v_client_id, v_client_platforms
  FROM clients WHERE slug = v_client_slug AND active = TRUE;
  IF v_client_id IS NULL THEN
    RAISE EXCEPTION 'Cliente não encontrado ou inativo: %', v_client_slug;
  END IF;

  v_month_start := (v_month || '-01')::DATE;
  v_month_end := (v_month_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  FOR v_post IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'posts', '[]'::JSONB)) LOOP
    v_post_idx := v_post_idx + 1;

    IF (v_post->>'date')::DATE NOT BETWEEN v_month_start AND v_month_end THEN
      RAISE EXCEPTION 'Post %: data % fora do mês %', v_post_idx, v_post->>'date', v_month;
    END IF;

    v_external_id := v_post->>'external_id';
    IF v_external_id IS NULL OR length(trim(v_external_id)) = 0 THEN
      RAISE EXCEPTION 'Post %: campo external_id é obrigatório', v_post_idx;
    END IF;
    IF v_external_id !~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' AND length(v_external_id) > 1 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): formato inválido. Use minúsculas, números e hífen.', v_post_idx, v_external_id;
    END IF;

    v_title := v_post->>'title';
    IF v_title IS NULL OR length(trim(v_title)) = 0 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): campo title é obrigatório', v_post_idx, v_external_id;
    END IF;
    IF length(v_title) > 30 THEN
      RAISE EXCEPTION 'Post % (external_id "%"): title tem % caracteres, máximo 30', v_post_idx, v_external_id, length(v_title);
    END IF;

    -- Validação de plataformas: rejeita JSON que trouxer plataforma não habilitada
    v_post_has_instagram := (v_post->>'instagram') IS NOT NULL AND length(trim(v_post->>'instagram')) > 0;
    v_post_has_linkedin  := (v_post->>'linkedin')  IS NOT NULL AND length(trim(v_post->>'linkedin'))  > 0;
    v_post_has_tiktok    := (v_post->>'tiktok')    IS NOT NULL AND length(trim(v_post->>'tiktok'))    > 0;

    IF v_post_has_linkedin AND NOT ('linkedin' = ANY(v_client_platforms)) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): cliente "%" não tem LinkedIn habilitado. Remova o campo linkedin.', v_post_idx, v_external_id, v_client_slug;
    END IF;
    IF v_post_has_tiktok AND NOT ('tiktok' = ANY(v_client_platforms)) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): cliente "%" não tem TikTok habilitado. Remova o campo tiktok.', v_post_idx, v_external_id, v_client_slug;
    END IF;
    IF v_post_has_instagram AND NOT ('instagram' = ANY(v_client_platforms)) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): cliente "%" não tem Instagram habilitado. Remova o campo instagram.', v_post_idx, v_external_id, v_client_slug;
    END IF;
    -- Exige pelo menos uma plataforma habilitada do cliente preenchida
    IF NOT (v_post_has_instagram OR v_post_has_linkedin OR v_post_has_tiktok) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): pelo menos uma plataforma habilitada do cliente deve ter caption preenchida', v_post_idx, v_external_id;
    END IF;

    IF v_external_id = ANY(v_imported_external_ids) THEN
      RAISE EXCEPTION 'Post % (external_id "%"): external_id duplicado dentro do JSON', v_post_idx, v_external_id;
    END IF;
    v_imported_external_ids := array_append(v_imported_external_ids, v_external_id);

    SELECT id INTO v_existing_post_id
    FROM posts
    WHERE client_id = v_client_id AND external_id = v_external_id;

    IF v_existing_post_id IS NOT NULL THEN
      UPDATE posts SET
        date = (v_post->>'date')::DATE,
        time = (v_post->>'time')::TIME,
        title = v_title,
        format = v_post->>'format',
        pillar = v_post->>'pillar',
        instagram = v_post->>'instagram',
        linkedin = v_post->>'linkedin',
        tiktok = v_post->>'tiktok',
        briefing_summary = v_post->>'briefing_summary',
        briefing_full = v_post->'briefing_full'
      WHERE id = v_existing_post_id;
      v_updated_count := v_updated_count + 1;
    ELSE
      INSERT INTO posts (
        client_id, external_id, date, time, title, format, pillar,
        instagram, linkedin, tiktok,
        briefing_summary, briefing_full,
        status, created_by
      ) VALUES (
        v_client_id, v_external_id,
        (v_post->>'date')::DATE, (v_post->>'time')::TIME,
        v_title, v_post->>'format', v_post->>'pillar',
        v_post->>'instagram', v_post->>'linkedin', v_post->>'tiktok',
        v_post->>'briefing_summary', v_post->'briefing_full',
        COALESCE(v_post->>'status', 'pending'),
        v_user_id
      );
      v_inserted_count := v_inserted_count + 1;
    END IF;
  END LOOP;

  IF p_replace THEN
    SELECT COUNT(*) INTO v_deleted_count
    FROM posts
    WHERE client_id = v_client_id
      AND date BETWEEN v_month_start AND v_month_end
      AND NOT (external_id = ANY(v_imported_external_ids));

    IF v_deleted_count > v_max_deletions THEN
      RAISE EXCEPTION 'Salvaguarda ativada: import removeria % posts (máximo permitido: %).', v_deleted_count, v_max_deletions;
    END IF;

    DELETE FROM posts
    WHERE client_id = v_client_id
      AND date BETWEEN v_month_start AND v_month_end
      AND NOT (external_id = ANY(v_imported_external_ids));
  END IF;

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
    'posts_deleted', v_deleted_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
