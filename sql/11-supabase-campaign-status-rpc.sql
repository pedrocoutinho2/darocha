-- ============================================================================
-- SQL 11: RPC DE STATUS DE CAMPANHA — FASE 3 (MÍDIA PAGA MULTI-MÊS)
-- ============================================================================
-- DEPENDÊNCIA: roda DEPOIS do SQL 10 (campaigns.status é criado lá). Esta RPC
-- só faz sentido com o schema da Fase 3 já aplicado.
--
-- CONTEXTO:
-- A Fase 3 deu à tabela `campaigns` uma máquina de status própria com 4 estados
-- (pending / approved / changes_requested / published), exibida na aba Tráfego
-- e usada na aprovação de campanhas pelo cliente.
--
-- Até aqui só existiam update_post_status e update_ad_status. Esta função é a
-- equivalente para campanhas: espelha update_ad_status (SECURITY DEFINER +
-- public.can_see_client), porém com os 4 estados da Fase 3.
--
-- REGRAS DE PERMISSÃO:
-- - Só quem enxerga o cliente da campanha (can_see_client) pode mexer.
-- - Cliente pode apenas 'approved' ou 'changes_requested'.
-- - 'pending' (redefinir) e 'published' (publicar) são ações da agência
--   (editor/admin).
--
-- OBSERVAÇÃO:
-- Definição idêntica à efetivamente aplicada no banco (pg_get_functiondef).
-- O front chama via cloudSync.updateCampaignStatus -> sb.rpc('update_campaign_status').
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_campaign_status(campaign_id bigint, new_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  target_client BIGINT;
BEGIN
  SELECT c.client_id INTO target_client FROM campaigns c WHERE c.id = campaign_id;
  IF NOT public.can_see_client(target_client) THEN
    RAISE EXCEPTION 'Sem permissão';
  END IF;
  IF new_status NOT IN ('pending', 'approved', 'changes_requested', 'published') THEN
    RAISE EXCEPTION 'Status inválido';
  END IF;
  IF public.user_role() = 'cliente' AND new_status IN ('pending', 'published') THEN
    RAISE EXCEPTION 'Cliente não pode redefinir nem publicar';
  END IF;
  UPDATE campaigns SET status = new_status, updated_at = NOW() WHERE id = campaign_id;
END;
$function$;
