-- ============================================
-- Migration 003: RPC atomica add_inventory_item (M3)
--
-- Problema: o frontend fazia 2 inserts separados (inventory + movements).
-- Se a rede caisse entre eles, o item ficaria sem historico inicial.
--
-- Solucao: RPC unica que faz ambos numa transacao do plpgsql.
-- Bonus: valida is_admin() no banco (defesa em profundidade, alem do JS).
--
-- Idempotente: pode rodar varias vezes (CREATE OR REPLACE).
-- ============================================

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
  -- Auth obrigatorio
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Nao autenticado');
  END IF;

  -- So admin cadastra item (defesa em profundidade alem do JS)
  IF NOT is_admin() THEN
    RETURN json_build_object('error', 'Apenas administradores podem cadastrar itens');
  END IF;

  -- Validacoes basicas
  IF p_quantity < 0 THEN
    RETURN json_build_object('error', 'Quantidade nao pode ser negativa');
  END IF;

  IF EXISTS (SELECT 1 FROM inventory WHERE code = p_code) THEN
    RETURN json_build_object('error', 'Codigo ja existe no estoque');
  END IF;

  -- Derivar nome do responsavel do usuario autenticado
  SELECT COALESCE(
    raw_user_meta_data->>'nome',
    initcap(replace(split_part(email, '@', 1), '.', ' '))
  ) INTO v_responsible
  FROM auth.users WHERE id = v_user_id;

  -- INSERT em inventory
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

  -- Se tem saldo inicial, registra ENTRADA no historico
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
    'success', true,
    'id', v_new_id,
    'code', p_code,
    'description', p_description
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION add_inventory_item(
  TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT
) TO authenticated;
