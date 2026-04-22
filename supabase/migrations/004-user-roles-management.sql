-- ============================================
-- Migration 004: gestao de roles via UI (admin promove/rebaixa)
--
-- Adiciona:
--   - policies INSERT/UPDATE/DELETE em user_roles (so admin)
--   - RPC set_user_role(p_user_id, p_role)  — com 3 travas:
--       a) caller precisa ser admin
--       b) admin nao pode rebaixar a si mesmo (evita lockout)
--       c) nao pode rebaixar o ultimo admin (sistema sempre tem >=1)
--   - RPC list_users_with_roles()  — expoe email+role ao frontend
--     sem dar acesso direto a auth.users
--
-- Idempotente.
-- ============================================

-- ============================================
-- 1. Policies de escrita em user_roles
-- ============================================

DROP POLICY IF EXISTS "user_roles_insert_admin" ON user_roles;
DROP POLICY IF EXISTS "user_roles_update_admin" ON user_roles;
DROP POLICY IF EXISTS "user_roles_delete_admin" ON user_roles;

CREATE POLICY "user_roles_insert_admin" ON user_roles
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());

CREATE POLICY "user_roles_update_admin" ON user_roles
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

CREATE POLICY "user_roles_delete_admin" ON user_roles
  FOR DELETE TO authenticated
  USING (is_admin());

-- ============================================
-- 2. RPC set_user_role — com travas de seguranca
-- ============================================

CREATE OR REPLACE FUNCTION set_user_role(p_user_id UUID, p_role TEXT)
RETURNS JSON AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_current_role TEXT;
  v_admin_count INT;
BEGIN
  -- Precisa estar autenticado
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Nao autenticado');
  END IF;

  -- Precisa ser admin
  IF NOT is_admin() THEN
    RETURN json_build_object('error', 'Apenas administradores podem alterar roles');
  END IF;

  -- Validar role
  IF p_role NOT IN ('admin', 'user') THEN
    RETURN json_build_object('error', 'Role deve ser admin ou user');
  END IF;

  -- Alvo precisa existir em auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RETURN json_build_object('error', 'Usuario nao encontrado');
  END IF;

  -- Trava A: admin nao pode rebaixar a si mesmo
  IF p_user_id = v_caller AND p_role <> 'admin' THEN
    RETURN json_build_object('error', 'Voce nao pode rebaixar a si mesmo');
  END IF;

  -- Pegar role atual (pode ser null se alvo nao tiver linha)
  SELECT role INTO v_current_role FROM user_roles WHERE user_id = p_user_id;

  -- Trava B: nao rebaixar o ultimo admin
  IF v_current_role = 'admin' AND p_role <> 'admin' THEN
    SELECT count(*) INTO v_admin_count FROM user_roles WHERE role = 'admin';
    IF v_admin_count <= 1 THEN
      RETURN json_build_object('error', 'Nao e possivel rebaixar o ultimo admin. Promova outro usuario antes.');
    END IF;
  END IF;

  -- Aplicar upsert
  INSERT INTO user_roles (user_id, role)
  VALUES (p_user_id, p_role)
  ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

  RETURN json_build_object('success', true, 'user_id', p_user_id, 'role', p_role);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION set_user_role(UUID, TEXT) TO authenticated;

-- ============================================
-- 3. RPC list_users_with_roles — listagem segura
-- ============================================

CREATE OR REPLACE FUNCTION list_users_with_roles()
RETURNS TABLE(user_id UUID, email TEXT, role TEXT, is_self BOOLEAN) AS $$
  SELECT
    u.id AS user_id,
    u.email::TEXT,
    COALESCE(ur.role, 'user') AS role,
    (u.id = auth.uid()) AS is_self
  FROM auth.users u
  LEFT JOIN user_roles ur ON ur.user_id = u.id
  WHERE is_admin()  -- filtro: retorna vazio se quem chama nao e admin
  ORDER BY u.email;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION list_users_with_roles() TO authenticated;
