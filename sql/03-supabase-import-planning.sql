-- ============================================================================
-- IMPORT DE PLANEJAMENTO MENSAL
-- ============================================================================
-- Tabela import_history (auditoria) + RPCs check_planning_exists e
-- import_planning. Suportam o botão "Importar Planejamento" do painel.
-- ============================================================================

CREATE TABLE IF NOT EXISTS import_history (
  id              BIGSERIAL PRIMARY KEY,
  client_id       BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  month           TEXT NOT NULL,
  imported_by     UUID NOT NULL REFERENCES profiles(id),
  imported_at     TIMESTAMPTZ DEFAULT NOW(),
  posts_count     INT NOT NULL DEFAULT 0,
  campaigns_count INT NOT NULL DEFAULT 0,
  ads_count       INT NOT NULL DEFAULT 0,
  replaced        BOOLEAN NOT NULL DEFAULT FALSE,
  raw_payload     JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_import_history_client_month ON import_history(client_id, month);

ALTER TABLE import_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Editor/admin vê histórico" ON import_history FOR SELECT
  USING (public.is_editor_or_admin());
CREATE POLICY "Editor/admin grava histórico" ON import_history FOR INSERT
  WITH CHECK (public.is_editor_or_admin() AND imported_by = auth.uid());

CREATE OR REPLACE FUNCTION public.check_planning_exists(
  p_client_id BIGINT, p_month TEXT
) RETURNS JSON AS $$
DECLARE
  v_post_count INT; v_campaign_count INT; v_ad_count INT;
  v_month_start DATE; v_month_end DATE;
BEGIN
  IF NOT public.is_editor_or_admin() THEN
    RAISE EXCEPTION 'Sem permissão pra consultar planejamentos';
  END IF;
  v_month_start := (p_month || '-01')::DATE;
  v_month_end := (v_month_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
  SELECT COUNT(*) INTO v_post_count FROM posts
    WHERE client_id = p_client_id AND date BETWEEN v_month_start AND v_month_end;
  SELECT COUNT(*) INTO v_campaign_count FROM campaigns
    WHERE client_id = p_client_id AND start_date <= v_month_end AND end_date >= v_month_start;
  SELECT COUNT(*) INTO v_ad_count FROM ads a JOIN campaigns c ON c.id = a.campaign_id
    WHERE c.client_id = p_client_id AND a.start_date <= v_month_end AND a.end_date >= v_month_start;
  RETURN json_build_object(
    'exists', (v_post_count + v_campaign_count) > 0,
    'posts_count', v_post_count, 'campaigns_count', v_campaign_count, 'ads_count', v_ad_count,
    'month_start', v_month_start, 'month_end', v_month_end
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
    IF (v_post->>'date')::DATE NOT BETWEEN v_month_start AND v_month_end THEN
      RAISE EXCEPTION 'Post com data fora do mês'; END IF;
    INSERT INTO posts (client_id, date, time, format, pillar, instagram, linkedin,
                       briefing_summary, briefing_full, status, created_by)
    VALUES (v_client_id, (v_post->>'date')::DATE, (v_post->>'time')::TIME,
            v_post->>'format', v_post->>'pillar', v_post->>'instagram', v_post->>'linkedin',
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

GRANT EXECUTE ON FUNCTION public.check_planning_exists(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.import_planning(JSONB, BOOLEAN) TO authenticated;
