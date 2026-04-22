-- ============================================
-- Migration 001: endurecer move_inventory (A2 + A3)
--
-- A2: adicionar SET search_path = public, pg_temp
--     (mitiga search_path hijacking em SECURITY DEFINER)
-- A3: derivar user_id e responsible de auth.uid() em vez de
--     confiar nos parametros enviados pelo cliente
--     (evita impersonacao no historico)
--
-- Compativel com o frontend atual: a assinatura mantem
-- p_user_id e p_responsible para nao quebrar chamadas
-- existentes, mas os valores sao IGNORADOS internamente.
-- ============================================

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
  -- Requer usuario autenticado (anon nao pode chamar)
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Nao autenticado');
  END IF;

  -- Derivar nome do usuario autenticado (NAO confiar em p_responsible)
  SELECT COALESCE(
    raw_user_meta_data->>'nome',
    initcap(replace(split_part(email, '@', 1), '.', ' '))
  ) INTO v_responsible
  FROM auth.users WHERE id = v_user_id;

  -- Validacoes
  IF p_type NOT IN ('ENTRADA', 'SAIDA') THEN
    RETURN json_build_object('error', 'Type must be ENTRADA or SAIDA');
  END IF;

  IF p_quantity <= 0 THEN
    RETURN json_build_object('error', 'Quantity must be greater than zero');
  END IF;

  -- Row lock para prevenir race condition
  SELECT * INTO v_item FROM inventory WHERE id = p_item_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Item not found');
  END IF;

  -- Calcular novo saldo
  IF p_type = 'SAIDA' THEN
    IF p_quantity > v_item.quantity THEN
      RETURN json_build_object('error', 'Saldo insuficiente. Disponivel: ' || v_item.quantity);
    END IF;
    v_new_qty := v_item.quantity - p_quantity;
  ELSE
    v_new_qty := v_item.quantity + p_quantity;
  END IF;

  -- Atualizar inventario
  UPDATE inventory SET quantity = v_new_qty, last_movement = now()
  WHERE id = p_item_id;

  -- Gravar movimento (imutavel) com usuario autenticado real
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
