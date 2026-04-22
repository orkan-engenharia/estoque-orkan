-- ============================================
-- Migration 002: roles (admin vs user) + RLS restrita
--
-- A1: fecha o buraco de RLS aberta (USING true em tudo).
-- Modelo:
--   - admin: pode INSERT/UPDATE/DELETE em inventory + listas mestres
--   - user:  pode SELECT tudo, mas nao cria/edita itens
--   - todos (autenticados): podem fazer ENTRADA/SAIDA (via RPC move_inventory)
--   - movements: historico IMUTAVEL — sem UPDATE/DELETE (nem admin)
--
-- Idempotente: pode rodar varias vezes sem quebrar.
-- ============================================

-- ============================================
-- 1. Tabela user_roles
-- ============================================

CREATE TABLE IF NOT EXISTS user_roles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

-- Usuario pode ler o proprio role (pra frontend decidir UI)
DROP POLICY IF EXISTS "user_roles_select_self" ON user_roles;
CREATE POLICY "user_roles_select_self" ON user_roles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Remover policy recursiva se existir (versao anterior causava loop infinito)
DROP POLICY IF EXISTS "user_roles_select_admin" ON user_roles;
-- A policy user_roles_select_admin sera recriada DEPOIS da funcao is_admin()
-- usando is_admin() (SECURITY DEFINER bypassa RLS evitando recursao)

-- Escrita em user_roles: SO admin (gerenciar via SQL Editor por enquanto)
-- Nao criamos policy de INSERT/UPDATE/DELETE para authenticated — nada passa.

-- ============================================
-- 2. Funcao is_admin() — helper reutilizavel
-- ============================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Permitir que authenticated chame is_admin() (ja eh padrao, mas explicito)
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;

-- Agora que is_admin() existe, criar policy admin_select sem recursao
CREATE POLICY "user_roles_select_admin" ON user_roles
  FOR SELECT TO authenticated
  USING (is_admin());

-- ============================================
-- 3. Reescrever policies de inventory
-- ============================================

DROP POLICY IF EXISTS "inventory_select" ON inventory;
DROP POLICY IF EXISTS "inventory_insert" ON inventory;
DROP POLICY IF EXISTS "inventory_update" ON inventory;
DROP POLICY IF EXISTS "inventory_delete" ON inventory;
DROP POLICY IF EXISTS "inventory_select_authenticated" ON inventory;
DROP POLICY IF EXISTS "inventory_insert_admin" ON inventory;
DROP POLICY IF EXISTS "inventory_update_admin" ON inventory;
DROP POLICY IF EXISTS "inventory_delete_admin" ON inventory;

-- SELECT: qualquer autenticado (todo mundo ve o estoque)
CREATE POLICY "inventory_select_authenticated" ON inventory
  FOR SELECT TO authenticated
  USING (true);

-- INSERT / UPDATE / DELETE: so admin
CREATE POLICY "inventory_insert_admin" ON inventory
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());

CREATE POLICY "inventory_update_admin" ON inventory
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

CREATE POLICY "inventory_delete_admin" ON inventory
  FOR DELETE TO authenticated
  USING (is_admin());

-- ============================================
-- 4. Policies de movements — historico imutavel
-- ============================================

DROP POLICY IF EXISTS "movements_select" ON movements;
DROP POLICY IF EXISTS "movements_insert" ON movements;
DROP POLICY IF EXISTS "movements_update" ON movements;
DROP POLICY IF EXISTS "movements_delete" ON movements;
DROP POLICY IF EXISTS "movements_select_authenticated" ON movements;
DROP POLICY IF EXISTS "movements_insert_authenticated" ON movements;

-- SELECT: todos autenticados
CREATE POLICY "movements_select_authenticated" ON movements
  FOR SELECT TO authenticated
  USING (true);

-- INSERT direto (raramente usado — RPC move_inventory eh SECURITY DEFINER e bypassa RLS,
-- mas se algum fluxo inserir direto, qualquer autenticado pode)
CREATE POLICY "movements_insert_authenticated" ON movements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- SEM policy de UPDATE/DELETE: historico e imutavel ate para admin
-- (audit trail principle). Mudancas exigem migration manual.

-- ============================================
-- 5. Policies de inventory_audit
-- ============================================

DROP POLICY IF EXISTS "audit_select" ON inventory_audit;
DROP POLICY IF EXISTS "audit_insert" ON inventory_audit;
DROP POLICY IF EXISTS "audit_select_authenticated" ON inventory_audit;
DROP POLICY IF EXISTS "audit_insert_authenticated" ON inventory_audit;

CREATE POLICY "audit_select_authenticated" ON inventory_audit
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "audit_insert_authenticated" ON inventory_audit
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Sem UPDATE/DELETE — auditoria imutavel.

-- ============================================
-- 6. Seed dos roles atuais
-- ============================================
-- Helena = admin, teste = user. Outros usuarios caem em 'user' por default
-- (mas como nao tem trigger de auto-insert, ficam SEM role ate admin cadastrar).
-- Se um usuario nao tem linha em user_roles, is_admin() retorna false — seguro.

INSERT INTO user_roles (user_id, role)
SELECT id, 'admin' FROM auth.users WHERE email = 'helena.alencar@orkan.com.br'
ON CONFLICT (user_id) DO UPDATE SET role = 'admin';

INSERT INTO user_roles (user_id, role)
SELECT id, 'user' FROM auth.users WHERE email = 'teste@orkan.com.br'
ON CONFLICT (user_id) DO UPDATE SET role = 'user';

-- ============================================
-- 7. Trigger: novo usuario cadastrado vira 'user' por padrao
-- ============================================
CREATE OR REPLACE FUNCTION assign_default_role()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'user')
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS on_auth_user_created_assign_role ON auth.users;
CREATE TRIGGER on_auth_user_created_assign_role
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION assign_default_role();
