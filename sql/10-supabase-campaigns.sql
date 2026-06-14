-- ============================================================================
-- SQL 10: MÍDIA PAGA FASE 3 — NETWORKS, STATUS, EXTERNAL_ID + IMPORT ESTENDIDO
-- ============================================================================
-- CONTEXTO:
-- A Fase 3 transforma a aba Tráfego em planejamento de mídia paga multi-mês.
-- Para isso o schema de campaigns/ads/clients ganhou:
--   - clients.ad_networks  — quais redes de mídia paga o cliente usa
--   - campaigns.networks[]  — redes da campanha (substitui o legado platform)
--   - campaigns.status      — máquina de aprovação própria da campanha
--   - campaigns.external_id — idempotência do import (único por cliente)
--   - ads.network           — rede do anúncio (1 rede por ad)
--   - ads.external_id       — idempotência do import (único por campanha)
-- e import_planning passou a importar campanhas + anúncios além de posts.
--
-- IMPORTANTE:
-- Os blocos 1-3 (schema) JÁ FORAM APLICADOS no banco de produção via SQL Editor.
-- Este arquivo é o versionamento dessa migração. Tudo aqui é IDEMPOTENTE
-- (ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS, UPDATEs com guards),
-- então é seguro rodar do zero num setup novo e NÃO precisa re-rodar em produção.
--
-- O legado campaigns.platform é preservado como coluna, mas a UI não o usa mais
-- (só serve de fallback de leitura pra campanhas ainda não migradas).
--
-- Bloco 4 (import_planning) é a definição REAL aplicada no banco, capturada via
-- pg_get_functiondef — inclui o COALESCE de budget_cents e a validação de redes.
-- A RPC de status de campanha (update_campaign_status) vem no SQL 11, depois
-- deste, porque depende de campaigns.status criado aqui.
-- ============================================================================


-- ============================================================================
-- BLOCO 1: clients.ad_networks — redes de mídia paga habilitadas por cliente
-- ============================================================================
ALTER TABLE clients ADD COLUMN IF NOT EXISTS ad_networks TEXT[] DEFAULT ARRAY[]::TEXT[];

UPDATE clients SET ad_networks = ARRAY['meta','linkedin','google'] WHERE slug = 'telecall';
UPDATE clients SET ad_networks = ARRAY['meta','tiktok','google'] WHERE slug IN ('cna-taquara','cna-queimados','jr-hoteis');


-- ============================================================================
-- BLOCO 2: campaigns — external_id, status, networks (migra platform legado)
-- ============================================================================
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS networks TEXT[] DEFAULT ARRAY[]::TEXT[];

-- 2.1) Migra o platform legado pra networks[] (só onde networks ainda está vazio)
UPDATE campaigns SET networks = ARRAY[platform]
WHERE platform IS NOT NULL AND (networks IS NULL OR array_length(networks,1) IS NULL);

-- 2.2) Gera external_id sintético pras campanhas existentes que não têm
UPDATE campaigns c SET external_id = cl.slug || '-camp-' || to_char(COALESCE(c.start_date, c.created_at::date), 'YYYY-MM') || '-' || c.id
FROM clients cl WHERE cl.id = c.client_id AND c.external_id IS NULL;

-- 2.3) Agora que toda campanha tem external_id, torna NOT NULL + único por cliente
ALTER TABLE campaigns ALTER COLUMN external_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS campaigns_client_external_uniq ON campaigns(client_id, external_id);


-- ============================================================================
-- BLOCO 3: ads — network, external_id (deriva do platform/external da campanha)
-- ============================================================================
ALTER TABLE ads ADD COLUMN IF NOT EXISTS network TEXT;
ALTER TABLE ads ADD COLUMN IF NOT EXISTS external_id TEXT;

-- 3.1) Deriva a rede do ad a partir do platform legado da campanha
UPDATE ads a SET network = c.platform
FROM campaigns c WHERE c.id = a.campaign_id AND a.network IS NULL;

-- 3.2) Gera external_id do ad a partir do external_id da campanha + code
UPDATE ads a SET external_id = c.external_id || '-' || lower(a.code)
FROM campaigns c WHERE c.id = a.campaign_id AND a.external_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ads_campaign_external_uniq ON ads(campaign_id, external_id);


-- ============================================================================
-- BLOCO 4: import_planning estendida — posts + campanhas + anúncios
-- ============================================================================
-- Evolução da import_planning do SQL 08: além de fazer upsert idempotente de
-- posts (por external_id), agora importa campanhas e seus anúncios da Fase 3.
-- Valida redes contra clients.ad_networks (campanha) e contra as redes da
-- própria campanha (ad). budget_cents usa COALESCE pra preservar valor existente
-- num update quando o JSON não trouxer o campo.
-- Definição abaixo é idêntica à aplicada no banco (pg_get_functiondef).

CREATE OR REPLACE FUNCTION public.import_planning(p_payload jsonb, p_replace boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_client_slug TEXT;
  v_client_id BIGINT;
  v_client_platforms TEXT[];
  v_client_ad_networks TEXT[];
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
  v_camp JSONB;
  v_camp_idx INT := 0;
  v_camp_external_id TEXT;
  v_camp_name TEXT;
  v_camp_networks TEXT[];
  v_camp_network TEXT;
  v_existing_camp_id BIGINT;
  v_camp_id BIGINT;
  v_campaigns_inserted INT := 0;
  v_campaigns_updated INT := 0;
  v_imported_camp_external_ids TEXT[] := ARRAY[]::TEXT[];
  v_ad JSONB;
  v_ad_idx INT := 0;
  v_ad_external_id TEXT;
  v_ad_code TEXT;
  v_ad_network TEXT;
  v_existing_ad_id BIGINT;
  v_ads_inserted INT := 0;
  v_ads_updated INT := 0;
  v_imported_ad_external_ids TEXT[] := ARRAY[]::TEXT[];
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

  SELECT id, platforms, ad_networks INTO v_client_id, v_client_platforms, v_client_ad_networks
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

  -- ============ CAMPANHAS + ADS (Fase 3) ============
  FOR v_camp IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'campaigns', '[]'::JSONB)) LOOP
    v_camp_idx := v_camp_idx + 1;
    v_ad_idx := 0;

    v_camp_external_id := v_camp->>'external_id';
    IF v_camp_external_id IS NULL OR length(trim(v_camp_external_id)) = 0 THEN
      RAISE EXCEPTION 'Campanha %: campo external_id é obrigatório', v_camp_idx;
    END IF;
    IF v_camp_external_id !~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' AND length(v_camp_external_id) > 1 THEN
      RAISE EXCEPTION 'Campanha % (external_id "%"): formato inválido. Use minúsculas, números e hífen.', v_camp_idx, v_camp_external_id;
    END IF;

    IF v_camp_external_id = ANY(v_imported_camp_external_ids) THEN
      RAISE EXCEPTION 'Campanha % (external_id "%"): external_id duplicado dentro do JSON', v_camp_idx, v_camp_external_id;
    END IF;
    v_imported_camp_external_ids := array_append(v_imported_camp_external_ids, v_camp_external_id);

    v_camp_name := v_camp->>'name';
    IF v_camp_name IS NULL OR length(trim(v_camp_name)) = 0 THEN
      RAISE EXCEPTION 'Campanha % (external_id "%"): campo name é obrigatório', v_camp_idx, v_camp_external_id;
    END IF;

    IF v_camp->>'start_date' IS NULL OR length(trim(v_camp->>'start_date')) = 0 THEN
      RAISE EXCEPTION 'Campanha % (external_id "%"): campo start_date é obrigatório', v_camp_idx, v_camp_external_id;
    END IF;

    IF v_camp->'networks' IS NULL
       OR jsonb_typeof(v_camp->'networks') != 'array'
       OR jsonb_array_length(v_camp->'networks') = 0 THEN
      RAISE EXCEPTION 'Campanha % (external_id "%"): campo networks é obrigatório e deve ser array não-vazio', v_camp_idx, v_camp_external_id;
    END IF;
    v_camp_networks := ARRAY(SELECT jsonb_array_elements_text(v_camp->'networks'));

    FOREACH v_camp_network IN ARRAY v_camp_networks LOOP
      IF NOT (v_camp_network = ANY(v_client_ad_networks)) THEN
        RAISE EXCEPTION 'Campanha % (external_id "%"): rede "%" não habilitada pro cliente "%". Disponíveis: %',
          v_camp_idx, v_camp_external_id, v_camp_network, v_client_slug, array_to_string(v_client_ad_networks, ', ');
      END IF;
    END LOOP;

    SELECT id INTO v_existing_camp_id
    FROM campaigns
    WHERE client_id = v_client_id AND external_id = v_camp_external_id;

    IF v_existing_camp_id IS NOT NULL THEN
      UPDATE campaigns SET
        name = v_camp_name,
        description = v_camp->>'description',
        objective = v_camp->>'objective',
        networks = v_camp_networks,
        format = v_camp->>'format',
        budget_cents = COALESCE(NULLIF(v_camp->>'budget_cents','')::BIGINT, budget_cents),
        start_date = (v_camp->>'start_date')::DATE,
        end_date = NULLIF(v_camp->>'end_date','')::DATE,
        briefing_full = v_camp->'briefing_full'
      WHERE id = v_existing_camp_id;
      v_camp_id := v_existing_camp_id;
      v_campaigns_updated := v_campaigns_updated + 1;
    ELSE
      INSERT INTO campaigns (
        client_id, external_id, name, description, objective,
        networks, format, budget_cents, start_date, end_date,
        briefing_full, status
      ) VALUES (
        v_client_id, v_camp_external_id, v_camp_name, v_camp->>'description', v_camp->>'objective',
        v_camp_networks, v_camp->>'format', COALESCE(NULLIF(v_camp->>'budget_cents','')::BIGINT, 0),
        (v_camp->>'start_date')::DATE, NULLIF(v_camp->>'end_date','')::DATE,
        v_camp->'briefing_full', COALESCE(v_camp->>'status', 'pending')
      ) RETURNING id INTO v_camp_id;
      v_campaigns_inserted := v_campaigns_inserted + 1;
    END IF;

    FOR v_ad IN SELECT * FROM jsonb_array_elements(COALESCE(v_camp->'ads', '[]'::JSONB)) LOOP
      v_ad_idx := v_ad_idx + 1;

      v_ad_external_id := v_ad->>'external_id';
      IF v_ad_external_id IS NULL OR length(trim(v_ad_external_id)) = 0 THEN
        RAISE EXCEPTION 'Ad % da campanha "%": campo external_id é obrigatório', v_ad_idx, v_camp_external_id;
      END IF;
      IF v_ad_external_id !~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' AND length(v_ad_external_id) > 1 THEN
        RAISE EXCEPTION 'Ad % (external_id "%"): formato inválido. Use minúsculas, números e hífen.', v_ad_idx, v_ad_external_id;
      END IF;

      IF v_ad_external_id = ANY(v_imported_ad_external_ids) THEN
        RAISE EXCEPTION 'Ad % (external_id "%"): external_id duplicado dentro do JSON', v_ad_idx, v_ad_external_id;
      END IF;
      v_imported_ad_external_ids := array_append(v_imported_ad_external_ids, v_ad_external_id);

      v_ad_code := v_ad->>'code';
      IF v_ad_code IS NULL OR length(trim(v_ad_code)) = 0 THEN
        RAISE EXCEPTION 'Ad % (external_id "%"): campo code é obrigatório', v_ad_idx, v_ad_external_id;
      END IF;

      v_ad_network := v_ad->>'network';
      IF v_ad_network IS NULL OR length(trim(v_ad_network)) = 0 THEN
        RAISE EXCEPTION 'Ad % (external_id "%"): campo network é obrigatório', v_ad_idx, v_ad_external_id;
      END IF;
      IF NOT (v_ad_network = ANY(v_camp_networks)) THEN
        RAISE EXCEPTION 'Ad % (external_id "%"): rede "%" não está nas redes da campanha "%" (%)',
          v_ad_idx, v_ad_external_id, v_ad_network, v_camp_external_id, array_to_string(v_camp_networks, ', ');
      END IF;

      SELECT id INTO v_existing_ad_id
      FROM ads
      WHERE campaign_id = v_camp_id AND external_id = v_ad_external_id;

      IF v_existing_ad_id IS NOT NULL THEN
        UPDATE ads SET
          code = v_ad_code,
          network = v_ad_network,
          headline = v_ad->>'headline',
          description = v_ad->>'description',
          format = v_ad->>'format',
          placement = v_ad->>'placement',
          cta = v_ad->>'cta',
          budget_cents = COALESCE(NULLIF(v_ad->>'budget_cents','')::BIGINT, budget_cents),
          start_date = NULLIF(v_ad->>'start_date','')::DATE,
          end_date = NULLIF(v_ad->>'end_date','')::DATE
        WHERE id = v_existing_ad_id;
        v_ads_updated := v_ads_updated + 1;
      ELSE
        INSERT INTO ads (
          campaign_id, external_id, code, network,
          headline, description, format, placement, cta,
          budget_cents, start_date, end_date, status
        ) VALUES (
          v_camp_id, v_ad_external_id, v_ad_code, v_ad_network,
          v_ad->>'headline', v_ad->>'description', v_ad->>'format', v_ad->>'placement', v_ad->>'cta',
          COALESCE(NULLIF(v_ad->>'budget_cents','')::BIGINT, 0),
          NULLIF(v_ad->>'start_date','')::DATE, NULLIF(v_ad->>'end_date','')::DATE,
          COALESCE(v_ad->>'status', 'pending')
        );
        v_ads_inserted := v_ads_inserted + 1;
      END IF;
    END LOOP;
  END LOOP;

  INSERT INTO import_history (
    client_id, month, imported_by,
    posts_count, campaigns_count, ads_count,
    replaced, raw_payload
  ) VALUES (
    v_client_id, v_month, v_user_id,
    v_inserted_count + v_updated_count,
    v_campaigns_inserted + v_campaigns_updated,
    v_ads_inserted + v_ads_updated,
    p_replace AND v_deleted_count > 0,
    p_payload
  );

  RETURN json_build_object(
    'success', true,
    'posts_inserted', v_inserted_count,
    'posts_updated', v_updated_count,
    'posts_deleted', v_deleted_count,
    'campaigns_inserted', v_campaigns_inserted,
    'campaigns_updated', v_campaigns_updated,
    'ads_inserted', v_ads_inserted,
    'ads_updated', v_ads_updated
  );
END;
$function$;


-- ============================================================================
-- BLOCO 5: RLS — NO-OP
-- ============================================================================
-- Nada a fazer aqui. As policies row-level já existentes de campaigns e ads
-- (definidas no SQL 04-multiclient, baseadas em can_see_client / client_id)
-- são por LINHA, não por coluna — então as colunas novas desta migração
-- (networks, status, external_id, network) já entram automaticamente sob a
-- mesma proteção, sem precisar de policy nova. Cliente continua vendo só as
-- campanhas/ads do próprio client_id; editor/admin gerencia.
