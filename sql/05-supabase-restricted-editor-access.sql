-- ============================================================================
-- ADIÇÃO 3: ACESSO RESTRITO POR LISTA DE CLIENTES (TODOS OS ROLES)
-- ============================================================================
-- Rode este arquivo DEPOIS dos anteriores.
-- O que ele faz:
--   - Atualiza can_see_client para que TODOS os roles (admin, editor, cliente)
--     respeitem a lista user_clients quando ela tem itens.
--   - Lista vazia continua significando "acesso a todos" (apenas para admin/editor).
--   - Cliente role sempre precisa de pelo menos 1 cliente atribuído.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_see_client(target_client_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
  v_user_clients BIGINT[];
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();

  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  v_user_clients := public.user_client_ids();

  IF v_role = 'cliente' THEN
    RETURN target_client_id = ANY(v_user_clients);
  END IF;

  IF v_role IN ('admin', 'editor') THEN
    IF array_length(v_user_clients, 1) IS NULL OR array_length(v_user_clients, 1) = 0 THEN
      RETURN TRUE;
    ELSE
      RETURN target_client_id = ANY(v_user_clients);
    END IF;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
