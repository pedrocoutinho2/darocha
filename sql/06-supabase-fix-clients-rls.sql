-- ============================================================================
-- FIX 06: POLICY DE SELECT EM CLIENTS USA can_see_client()
-- ============================================================================
-- Bug detectado: a policy "Visualização de clientes" usava is_editor_or_admin()
-- diretamente, o que ignorava a lista de user_clients para editores. Resultado:
-- editor com clientes específicos atribuídos via user_clients ainda via TODOS
-- os clientes na tabela clients (apesar das outras tabelas — posts, campaigns,
-- ads, media — já estarem filtrando corretamente via can_see_client()).
--
-- Fix: substituir a policy para usar can_see_client(id) consistente com as
-- outras tabelas do sistema.
-- ============================================================================

DROP POLICY IF EXISTS "Visualização de clientes" ON clients;

CREATE POLICY "Visualização de clientes" ON clients FOR SELECT
  USING (can_see_client(id));
