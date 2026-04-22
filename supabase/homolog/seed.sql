-- ============================================
-- HOMOLOG seed: itens variados para rodar testes E2E
-- Roda depois do setup.sql e apos os usuarios existirem.
-- Idempotente: usa ON CONFLICT no code.
-- ============================================

INSERT INTO inventory (code, description, product, manufacturer, quantity, min_stock, location, unit, notes, last_movement, created_by) VALUES
  ('BRN001', 'BORNE CONEXAO 2.5MM AZUL', 'Borne', 'PHOENIX CONTACT', 50, 10, '01', 'peca', '', now(), 'Helena Alencar'),
  ('BRN002', 'BORNE DE TERRA 2.5MM VERDE', 'Borne', 'PHOENIX CONTACT', 30, 10, '01', 'peca', '', now(), 'Helena Alencar'),
  ('BRN003', 'BORNE DE PASSAGEM 4MM', 'Borne', 'WEIDMULLER', 20, 5, '01', 'peca', '', now(), 'Helena Alencar'),
  ('DSJ001', 'DISJUNTOR BIPOLAR 16A', 'Disjuntor', 'SIEMENS', 15, 5, '02', 'peca', '', now(), 'Helena Alencar'),
  ('DSJ002', 'DISJUNTOR TRIPOLAR 25A', 'Disjuntor', 'SIEMENS', 12, 3, '02', 'peca', '', now(), 'Helena Alencar'),
  ('DSJ003', 'DISJUNTOR MOTOR 10A', 'Disjuntor', 'EATON', 8, 2, '02', 'peca', '', now(), 'Helena Alencar'),
  ('CTT001', 'CONTATOR 9A 24VCC', 'Contator', 'SIEMENS', 10, 3, '03', 'peca', '', now(), 'Helena Alencar'),
  ('CTT002', 'CONTATOR 18A 220VCA', 'Contator', 'SCHNEIDER', 7, 2, '03', 'peca', '', now(), 'Helena Alencar'),
  ('REL001', 'RELE MINIATURA 24VCC', 'Rele', 'FINDER', 25, 10, '04', 'peca', '', now(), 'Helena Alencar'),
  ('REL002', 'RELE TEMPORIZADOR 0-60S', 'Rele', 'FINDER', 5, 2, '04', 'peca', '', now(), 'Helena Alencar'),
  ('SNS001', 'SENSOR INDUTIVO PNP M12', 'Sensor', 'SICK', 15, 5, '05', 'peca', '', now(), 'Helena Alencar'),
  ('SNS002', 'SENSOR CAPACITIVO M18', 'Sensor', 'SICK', 8, 2, '05', 'peca', '', now(), 'Helena Alencar'),
  ('BTO001', 'BOTAO LIGA VERDE', 'Botao', 'SIEMENS', 20, 5, '06', 'peca', '', now(), 'Helena Alencar'),
  ('BTO002', 'BOTAO EMERGENCIA VERMELHO', 'Botao', 'SIEMENS', 10, 3, '06', 'peca', '', now(), 'Helena Alencar'),
  ('MOD001', 'MODULO DIGITAL INPUT 16 CANAIS', 'Modulo', 'SIEMENS', 5, 2, '07', 'peca', '', now(), 'Helena Alencar'),
  ('MOD002', 'MODULO DIGITAL OUTPUT 16 CANAIS', 'Modulo', 'SIEMENS', 4, 2, '07', 'peca', '', now(), 'Helena Alencar'),
  ('FNT001', 'FONTE 24VCC 10A', 'Fonte', 'PHOENIX CONTACT', 6, 2, '08', 'peca', '', now(), 'Helena Alencar'),
  ('CAB001', 'CABO PP 3X2.5 PRETO', 'Cabo', 'PRYSMIAN', 100, 20, '09', 'metro', '', now(), 'Helena Alencar'),
  ('TMP001', 'TAMPA CEGA DIN', 'Tampa', 'SIEMENS', 30, 10, '10', 'peca', '', now(), 'Helena Alencar'),
  ('CPU001', 'CPU S7-1200 CPU 1214C', 'CPU', 'SIEMENS', 2, 1, '07', 'peca', '', now(), 'Helena Alencar')
ON CONFLICT (code) DO NOTHING;
