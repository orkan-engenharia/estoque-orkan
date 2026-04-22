-- ============================================
-- HOMOLOG: instalacao do zero
--
-- Rodar UMA VEZ no SQL Editor do projeto estoque-orkan-homolog
-- (https://earxvgvwjutgegxeclfn.supabase.co)
--
-- Inclui: schema + policies + funcoes (com A2/A3 ja aplicados)
--          + tabela de auditoria + coluna created_by
--          + user_roles com admin/user (ver migration 002)
--
-- Apos rodar:
--   1. Criar usuarios em Authentication > Users:
--      - helena.alencar@orkan.com.br / Orkan@2020
--      - teste@orkan.com.br          / Orkan@2020
--   2. Abrir estoque-app.html local (localhost) — autodetecta homolog
-- ============================================

-- ============================================
-- 1. SCHEMA (tabelas principais)
-- ============================================

DROP TABLE IF EXISTS historico CASCADE;
DROP TABLE IF EXISTS estoque CASCADE;
DROP TABLE IF EXISTS responsaveis CASCADE;

CREATE TABLE inventory (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  product TEXT NOT NULL,
  subtype TEXT,
  manufacturer TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  min_stock INTEGER NOT NULL DEFAULT 0,
  location TEXT NOT NULL,
  box_name TEXT DEFAULT '',
  unit TEXT NOT NULL DEFAULT 'peca',
  notes TEXT DEFAULT '',
  last_movement TIMESTAMPTZ,
  created_by TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE movements (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  moved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  code TEXT NOT NULL,
  description TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('ENTRADA', 'SAIDA')),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  responsible TEXT NOT NULL,
  destination TEXT,
  work_order TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  previous_balance INTEGER NOT NULL,
  new_balance INTEGER NOT NULL,
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE inventory_audit (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  inventory_id BIGINT NOT NULL REFERENCES inventory(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  changes JSONB NOT NULL
);

CREATE INDEX idx_inventory_code ON inventory(code);
CREATE INDEX idx_movements_code ON movements(code);
CREATE INDEX idx_movements_date ON movements(moved_at DESC);
CREATE INDEX idx_movements_responsible ON movements(responsible);
CREATE INDEX idx_movements_type ON movements(type);
CREATE INDEX idx_audit_inventory ON inventory_audit(inventory_id);
CREATE INDEX idx_audit_date ON inventory_audit(changed_at DESC);
CREATE INDEX idx_audit_user ON inventory_audit(user_id);

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER inventory_updated_at
  BEFORE UPDATE ON inventory
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER PUBLICATION supabase_realtime ADD TABLE inventory;
ALTER PUBLICATION supabase_realtime ADD TABLE movements;

-- ============================================
-- 2. ROLES (user_roles + is_admin) — precisa existir antes das policies
-- ============================================

CREATE TABLE user_roles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_roles_select_self" ON user_roles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Policies de escrita em user_roles: so admin (ver migration 004)
CREATE POLICY "user_roles_insert_admin" ON user_roles
  FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "user_roles_update_admin" ON user_roles
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "user_roles_delete_admin" ON user_roles
  FOR DELETE TO authenticated USING (is_admin());

-- is_admin precisa ser SECURITY DEFINER para rodar como owner e bypassar RLS
-- (evita recursao infinita quando usada em policies de user_roles)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;

-- Policy admin_select criada APOS is_admin para evitar recursao
CREATE POLICY "user_roles_select_admin" ON user_roles
  FOR SELECT TO authenticated
  USING (is_admin());

-- ============================================
-- 3. POLICIES (RLS) — usam is_admin()
-- ============================================

ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_select_authenticated" ON inventory
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "inventory_insert_admin" ON inventory
  FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "inventory_update_admin" ON inventory
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "inventory_delete_admin" ON inventory
  FOR DELETE TO authenticated USING (is_admin());

CREATE POLICY "movements_select_authenticated" ON movements
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "movements_insert_authenticated" ON movements
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
-- Sem UPDATE/DELETE em movements: historico imutavel

CREATE POLICY "audit_select_authenticated" ON inventory_audit
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "audit_insert_authenticated" ON inventory_audit
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
-- Sem UPDATE/DELETE em inventory_audit: auditoria imutavel

-- ============================================
-- 4. FUNCOES E TRIGGERS
-- ============================================

-- Restricao de dominio @orkan.com.br
CREATE OR REPLACE FUNCTION check_email_domain()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.email NOT LIKE '%@orkan.com.br' THEN
    RAISE EXCEPTION 'Only @orkan.com.br emails are allowed';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'enforce_email_domain') THEN
    CREATE TRIGGER enforce_email_domain
      BEFORE INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION check_email_domain();
  END IF;
END $$;

-- RPC move_inventory JA COM A2+A3 APLICADOS
-- (ver supabase/migrations/001-a2-a3-move-inventory-security.sql)
CREATE OR REPLACE FUNCTION move_inventory(
  p_item_id BIGINT,
  p_type TEXT,
  p_quantity INTEGER,
  p_responsible TEXT,
  p_destination TEXT DEFAULT NULL,
  p_work_order TEXT DEFAULT '',
  p_notes TEXT DEFAULT '',
  p_user_id UUID DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
  v_item RECORD;
  v_new_qty INTEGER;
  v_user_id UUID := auth.uid();
  v_responsible TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Nao autenticado');
  END IF;

  SELECT COALESCE(
    raw_user_meta_data->>'nome',
    initcap(replace(split_part(email, '@', 1), '.', ' '))
  ) INTO v_responsible
  FROM auth.users WHERE id = v_user_id;

  IF p_type NOT IN ('ENTRADA', 'SAIDA') THEN
    RETURN json_build_object('error', 'Type must be ENTRADA or SAIDA');
  END IF;

  IF p_quantity <= 0 THEN
    RETURN json_build_object('error', 'Quantity must be greater than zero');
  END IF;

  SELECT * INTO v_item FROM inventory WHERE id = p_item_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Item not found');
  END IF;

  IF p_type = 'SAIDA' THEN
    IF p_quantity > v_item.quantity THEN
      RETURN json_build_object('error', 'Saldo insuficiente. Disponivel: ' || v_item.quantity);
    END IF;
    v_new_qty := v_item.quantity - p_quantity;
  ELSE
    v_new_qty := v_item.quantity + p_quantity;
  END IF;

  UPDATE inventory SET quantity = v_new_qty, last_movement = now()
  WHERE id = p_item_id;

  INSERT INTO movements (
    code, description, type, quantity, responsible,
    destination, work_order, notes,
    previous_balance, new_balance, user_id
  ) VALUES (
    v_item.code, v_item.description, p_type, p_quantity, v_responsible,
    p_destination, p_work_order, p_notes,
    v_item.quantity, v_new_qty, v_user_id
  );

  RETURN json_build_object(
    'success', true,
    'previous_balance', v_item.quantity,
    'new_balance', v_new_qty,
    'code', v_item.code,
    'description', v_item.description
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- RPC atomica para cadastro de novo item (M3, ver migration 003)
-- Faz INSERT em inventory + movimento ENTRADA inicial numa transacao
CREATE OR REPLACE FUNCTION add_inventory_item(
  p_code TEXT,
  p_description TEXT,
  p_product TEXT,
  p_manufacturer TEXT,
  p_quantity INTEGER,
  p_location TEXT,
  p_subtype TEXT DEFAULT NULL,
  p_min_stock INTEGER DEFAULT 0,
  p_unit TEXT DEFAULT 'peca',
  p_notes TEXT DEFAULT '',
  p_destination TEXT DEFAULT NULL,
  p_work_order TEXT DEFAULT ''
) RETURNS JSON AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_responsible TEXT;
  v_new_id BIGINT;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Nao autenticado');
  END IF;
  IF NOT is_admin() THEN
    RETURN json_build_object('error', 'Apenas administradores podem cadastrar itens');
  END IF;
  IF p_quantity < 0 THEN
    RETURN json_build_object('error', 'Quantidade nao pode ser negativa');
  END IF;
  IF EXISTS (SELECT 1 FROM inventory WHERE code = p_code) THEN
    RETURN json_build_object('error', 'Codigo ja existe no estoque');
  END IF;

  SELECT COALESCE(
    raw_user_meta_data->>'nome',
    initcap(replace(split_part(email, '@', 1), '.', ' '))
  ) INTO v_responsible
  FROM auth.users WHERE id = v_user_id;

  INSERT INTO inventory (
    code, description, product, subtype, manufacturer,
    quantity, min_stock, location, box_name, unit, notes,
    last_movement, created_by
  ) VALUES (
    p_code, p_description, p_product, p_subtype, p_manufacturer,
    p_quantity, p_min_stock, p_location, '', p_unit, p_notes,
    v_now, v_responsible
  )
  RETURNING id INTO v_new_id;

  IF p_quantity > 0 THEN
    INSERT INTO movements (
      moved_at, code, description, type, quantity, responsible,
      destination, work_order, notes,
      previous_balance, new_balance, user_id
    ) VALUES (
      v_now, p_code, p_description, 'ENTRADA', p_quantity, v_responsible,
      p_destination, p_work_order, 'Cadastro inicial',
      0, p_quantity, v_user_id
    );
  END IF;

  RETURN json_build_object(
    'success', true, 'id', v_new_id,
    'code', p_code, 'description', p_description
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION add_inventory_item(
  TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT
) TO authenticated;

-- RPC para admin promover/rebaixar usuarios via UI (ver migration 004)
CREATE OR REPLACE FUNCTION set_user_role(p_user_id UUID, p_role TEXT)
RETURNS JSON AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_current_role TEXT;
  v_admin_count INT;
BEGIN
  IF v_caller IS NULL THEN RETURN json_build_object('error', 'Nao autenticado'); END IF;
  IF NOT is_admin() THEN RETURN json_build_object('error', 'Apenas administradores podem alterar roles'); END IF;
  IF p_role NOT IN ('admin', 'user') THEN RETURN json_build_object('error', 'Role deve ser admin ou user'); END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN RETURN json_build_object('error', 'Usuario nao encontrado'); END IF;
  IF p_user_id = v_caller AND p_role <> 'admin' THEN RETURN json_build_object('error', 'Voce nao pode rebaixar a si mesmo'); END IF;
  SELECT role INTO v_current_role FROM user_roles WHERE user_id = p_user_id;
  IF v_current_role = 'admin' AND p_role <> 'admin' THEN
    SELECT count(*) INTO v_admin_count FROM user_roles WHERE role = 'admin';
    IF v_admin_count <= 1 THEN
      RETURN json_build_object('error', 'Nao e possivel rebaixar o ultimo admin. Promova outro usuario antes.');
    END IF;
  END IF;
  INSERT INTO user_roles (user_id, role) VALUES (p_user_id, p_role)
  ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;
  RETURN json_build_object('success', true, 'user_id', p_user_id, 'role', p_role);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
GRANT EXECUTE ON FUNCTION set_user_role(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION list_users_with_roles()
RETURNS TABLE(user_id UUID, email TEXT, role TEXT, is_self BOOLEAN) AS $$
  SELECT u.id, u.email::TEXT, COALESCE(ur.role, 'user'), (u.id = auth.uid())
  FROM auth.users u LEFT JOIN user_roles ur ON ur.user_id = u.id
  WHERE is_admin()
  ORDER BY u.email;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp;
GRANT EXECUTE ON FUNCTION list_users_with_roles() TO authenticated;

-- Trigger: todo novo usuario vira 'user' por default
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

-- ============================================
-- 5. Promover helena a admin (rodar APOS criar os usuarios)
-- ============================================
-- Os usuarios sao criados no dashboard Authentication > Users.
-- O trigger acima marca cada novo cadastro como 'user'.
-- Aqui promovemos helena a admin:

INSERT INTO user_roles (user_id, role)
SELECT id, 'admin' FROM auth.users WHERE email = 'helena.alencar@orkan.com.br'
ON CONFLICT (user_id) DO UPDATE SET role = 'admin';
