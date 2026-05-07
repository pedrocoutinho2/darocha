-- ============================================================================
-- MULTI-CLIENTE — usuários com acesso a vários clientes
-- ============================================================================
-- Tabela user_clients (N×N) + funções administrativas para gerenciar usuários
-- e clientes. Substitui a função user_client_ids() para considerar a lista.
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_clients (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  client_id   BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, client_id)
);
CREATE INDEX IF NOT EXISTS idx_user_clients_user ON user_clients(user_id);
CREATE INDEX IF NOT EXISTS idx_user_clients_client ON user_clients(client_id);

ALTER TABLE user_clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Ver próprios vínculos ou todos (admin)" ON user_clients FOR SELECT
  USING (user_id = auth.uid() OR public.is_admin() OR public.is_editor_or_admin());
CREATE POLICY "Admin gerencia vínculos" ON user_clients FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.user_client_ids()
RETURNS BIGINT[] AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT cid FROM (
        SELECT client_id AS cid FROM profiles WHERE id = auth.uid() AND client_id IS NOT NULL
        UNION
        SELECT client_id AS cid FROM user_clients WHERE user_id = auth.uid()
      ) t WHERE cid IS NOT NULL
    ),
    ARRAY[]::BIGINT[]
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- can_see_client atualizada novamente pelo SQL 05 e 06
CREATE OR REPLACE FUNCTION public.can_see_client(target_client_id BIGINT)
RETURNS BOOLEAN AS $$
  SELECT
    public.is_editor_or_admin()
    OR target_client_id = ANY(public.user_client_ids());
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_user_id UUID, p_name TEXT, p_email TEXT, p_role TEXT, p_client_ids BIGINT[]
) RETURNS JSON AS $$
DECLARE v_updated_profile JSON;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Apenas administradores'; END IF;
  IF p_role NOT IN ('admin','editor','cliente') THEN RAISE EXCEPTION 'Role inválido'; END IF;

  UPDATE profiles SET name = p_name, email = p_email, role = p_role,
    client_id = CASE WHEN array_length(p_client_ids,1) > 0 THEN p_client_ids[1] ELSE NULL END
    WHERE id = p_user_id;

  DELETE FROM user_clients WHERE user_id = p_user_id;
  IF p_client_ids IS NOT NULL AND array_length(p_client_ids,1) > 0 THEN
    INSERT INTO user_clients (user_id, client_id)
      SELECT p_user_id, unnest(p_client_ids);
  END IF;

  SELECT json_build_object('id', id, 'name', name, 'email', email, 'role', role, 'client_id', client_id)
    INTO v_updated_profile FROM profiles WHERE id = p_user_id;
  RETURN v_updated_profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.admin_update_user(UUID, TEXT, TEXT, TEXT, BIGINT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_users()
RETURNS TABLE (id UUID, name TEXT, email TEXT, role TEXT, client_ids BIGINT[], client_names TEXT[]) AS $$
  SELECT p.id, p.name, p.email, p.role,
    COALESCE(ARRAY_AGG(c.id) FILTER (WHERE c.id IS NOT NULL), '{}'::BIGINT[]),
    COALESCE(ARRAY_AGG(c.name) FILTER (WHERE c.name IS NOT NULL), '{}'::TEXT[])
  FROM profiles p
  LEFT JOIN user_clients uc ON uc.user_id = p.id
  LEFT JOIN clients c ON c.id = uc.client_id
  WHERE public.is_admin()
  GROUP BY p.id, p.name, p.email, p.role
  ORDER BY p.role, p.name;
$$ LANGUAGE SQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.admin_list_users() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_create_client(
  p_name TEXT, p_slug TEXT, p_primary_color TEXT, p_logo_url TEXT
) RETURNS JSON AS $$
DECLARE v_client_id BIGINT; v_result JSON;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Apenas administradores'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN RAISE EXCEPTION 'Nome obrigatório'; END IF;
  IF p_slug IS NULL OR length(trim(p_slug)) = 0 THEN RAISE EXCEPTION 'Slug obrigatório'; END IF;
  IF p_slug !~ '^[a-z0-9-]+$' THEN RAISE EXCEPTION 'Slug inválido'; END IF;

  INSERT INTO clients (name, slug, primary_color, logo_url, active)
    VALUES (p_name, p_slug, COALESCE(p_primary_color, '#0066b3'), p_logo_url, TRUE)
    RETURNING id INTO v_client_id;

  SELECT json_build_object('id', id, 'name', name, 'slug', slug,
    'primary_color', primary_color, 'logo_url', logo_url)
    INTO v_result FROM clients WHERE id = v_client_id;
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.admin_create_client(TEXT, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_client(
  p_client_id BIGINT, p_name TEXT, p_primary_color TEXT, p_logo_url TEXT, p_active BOOLEAN
) RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Apenas administradores'; END IF;
  UPDATE clients SET name = COALESCE(p_name, name), primary_color = COALESCE(p_primary_color, primary_color),
    logo_url = p_logo_url, active = COALESCE(p_active, active), updated_at = NOW()
    WHERE id = p_client_id;
  SELECT json_build_object('id', id, 'name', name, 'slug', slug, 'primary_color', primary_color,
    'logo_url', logo_url, 'active', active)
    INTO v_result FROM clients WHERE id = p_client_id;
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.admin_update_client(BIGINT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

INSERT INTO user_clients (user_id, client_id)
  SELECT id, client_id FROM profiles
    WHERE client_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM user_clients uc
        WHERE uc.user_id = profiles.id AND uc.client_id = profiles.client_id);
