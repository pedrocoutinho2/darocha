-- ============================================================================
-- ADIÇÃO 7: COLUNA TITLE EM POSTS + VALIDAÇÃO NO IMPORT
-- ============================================================================
-- Adiciona campo title (até 30 chars) em posts. Esse campo substitui o pillar
-- como nome principal do post no calendário e demais visualizações do painel.
-- O pillar continua sendo usado para cor, filtragem e organização.
--
-- Estratégia de migração: coluna criada como nullable inicialmente, populada
-- com valor do pillar para os posts existentes (compat), depois tornada
-- NOT NULL. Posts importados a partir desta migration precisam vir com title.
-- ============================================================================

-- 1) Adiciona coluna nullable
ALTER TABLE posts ADD COLUMN IF NOT EXISTS title TEXT;

-- 2) Popula posts existentes usando pillar como título inicial
UPDATE posts SET title = pillar WHERE title IS NULL;

-- 3) Adiciona constraint de tamanho e NOT NULL
ALTER TABLE posts
  ALTER COLUMN title SET NOT NULL,
  ADD CONSTRAINT title_length_check CHECK (length(title) > 0 AND length(title) <= 30);

-- 4) Atualiza função import_planning para validar e gravar title
CREATE OR REPLACE FUNCTION public.import_planning(
  p_payload JSONB, p_replace BOOLEAN DEFAULT FALSE
) RETURNS JSON AS $$
DECLARE
  v_client_slug TEXT; v_client_id BIGINT; v_month TEXT;
  v_month_start DATE; v_month_end DATE;
  v_post JSONB; v_campaign JSONB; v_ad JSONB;
  v_new_campaign_id BIGINT;
  v_posts_count INT := 0; v_campaigns_count INT := 0; v_ads_count INT := 0;
  v_existing_posts INT; v_existing_campaigns INT;
  v_user_id UUID;
  v_post_idx INT := 0;
  v_title TEXT;
BEGIN
  IF NOT public.is_editor_or_admin() THEN RAISE EXCEPTION 'Sem permissão'; END IF;
  v_user_id := auth.uid();

  IF p_payload->>'version' IS NULL OR p_payload->>'version' != '1.0' THEN
    RAISE EXCEPTION 'Versão inválida'; END IF;
  IF p_payload->>'client_slug' IS NULL THEN RAISE EXCEPTION 'client_slug obrigatório'; END IF;
  IF p_payload->>'month' IS NULL OR (p_payload->>'month') !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'month inválido'; END IF;

  v_client_slug := p_payload->>'client_slug';
  v_month := p_payload->>'month';

  SELECT id INTO v_client_id FROM clients WHERE slug = v_client_slug AND active = TRUE;
  IF v_client_id IS NULL THEN RAISE EXCEPTION 'Cliente não encontrado'; END IF;

  v_month_start := (v_month || '-01')::DATE;
  v_month_end := (v_month_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  SELECT COUNT(*) INTO v_existing_posts FROM posts
    WHERE client_id = v_client_id AND date BETWEEN v_month_start AND v_month_end;
  SELECT COUNT(*) INTO v_existing_campaigns FROM campaigns
    WHERE client_id = v_client_id AND start_date <= v_month_end AND end_date >= v_month_start;

  IF (v_existing_posts + v_existing_campaigns) > 0 AND NOT p_replace THEN
    RAISE EXCEPTION 'Já existe planejamento para % neste mês. Use replace=TRUE.', v_client_slug;
  END IF;

  IF p_replace AND (v_existing_posts + v_existing_campaigns) > 0 THEN
    DELETE FROM posts WHERE client_id = v_client_id AND date BETWEEN v_month_start AND v_month_end;
    DELETE FROM campaigns WHERE client_id = v_client_id AND start_date <= v_month_end AND end_date >= v_month_start;
  END IF;

  FOR v_post IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'posts', '[]'::JSONB)) LOOP
    v_post_idx := v_post_idx + 1;
    IF (v_post->>'date')::DATE NOT BETWEEN v_month_start AND v_month_end THEN
      RAISE EXCEPTION 'Post % com data fora do mês', v_post_idx; END IF;

    -- Validação de title (NOVA)
    v_title := v_post->>'title';
    IF v_title IS NULL OR length(trim(v_title)) = 0 THEN
      RAISE EXCEPTION 'Post %: campo title é obrigatório', v_post_idx;
    END IF;
    IF length(v_title) > 30 THEN
      RAISE EXCEPTION 'Post %: title tem % caracteres, máximo é 30', v_post_idx, length(v_title);
    END IF;

    INSERT INTO posts (client_id, date, time, title, format, pillar, instagram, linkedin,
                       briefing_summary, briefing_full, status, created_by)
    VALUES (v_client_id, (v_post->>'date')::DATE, (v_post->>'time')::TIME,
            v_title, v_post->>'format', v_post->>'pillar',
            v_post->>'instagram', v_post->>'linkedin',
            v_post->>'briefing_summary', v_post->'briefing_full',
            COALESCE(v_post->>'status','pending'), v_user_id);
    v_posts_count := v_posts_count + 1;
  END LOOP;

  FOR v_campaign IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'campaigns', '[]'::JSONB)) LOOP
    INSERT INTO campaigns (client_id, platform, name, description, objective, format,
                           budget_cents, start_date, end_date, briefing_full)
    VALUES (v_client_id, v_campaign->>'platform', v_campaign->>'name',
            v_campaign->>'description', v_campaign->>'objective', v_campaign->>'format',
            ((v_campaign->>'budget_brl')::NUMERIC * 100)::BIGINT,
            (v_campaign->>'start_date')::DATE, (v_campaign->>'end_date')::DATE,
            v_campaign->'briefing_full')
    RETURNING id INTO v_new_campaign_id;
    v_campaigns_count := v_campaigns_count + 1;

    FOR v_ad IN SELECT * FROM jsonb_array_elements(COALESCE(v_campaign->'ads', '[]'::JSONB)) LOOP
      INSERT INTO ads (campaign_id, code, headline, description, format, placement, cta,
                       budget_cents, start_date, end_date, status)
      VALUES (v_new_campaign_id, v_ad->>'code', v_ad->>'headline', v_ad->>'description',
              v_ad->>'format', v_ad->>'placement', v_ad->>'cta',
              ((v_ad->>'budget_brl')::NUMERIC * 100)::BIGINT,
              (v_ad->>'start_date')::DATE, (v_ad->>'end_date')::DATE,
              COALESCE(v_ad->>'status','pending'));
      v_ads_count := v_ads_count + 1;
    END LOOP;
  END LOOP;

  INSERT INTO import_history (client_id, month, imported_by, posts_count, campaigns_count, ads_count, replaced, raw_payload)
  VALUES (v_client_id, v_month, v_user_id, v_posts_count, v_campaigns_count, v_ads_count,
          p_replace AND (v_existing_posts + v_existing_campaigns) > 0, p_payload);

  RETURN json_build_object('success', true, 'posts_imported', v_posts_count,
    'campaigns_imported', v_campaigns_count, 'ads_imported', v_ads_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
