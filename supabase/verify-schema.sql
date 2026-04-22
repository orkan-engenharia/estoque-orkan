-- ============================================
-- Smoke test: verifica que schema esta completo apos migrations.
-- Uso: PGPASSWORD=... psql "..." -f supabase/verify-schema.sql
--
-- Esperado:
--   4 tabelas, 6 funcoes (4 SECURITY DEFINER), 10 policies, 3 triggers
-- ============================================

\echo '=== Tabelas (esperado: 4) ==='
SELECT count(*) AS n FROM information_schema.tables
 WHERE table_schema='public' AND table_name IN ('inventory','movements','inventory_audit','user_roles');

\echo '=== Funcoes (esperado: 6, destas 4 SECURITY DEFINER) ==='
SELECT proname, prosecdef AS security_definer
  FROM pg_proc
 WHERE proname IN ('move_inventory','add_inventory_item','is_admin','assign_default_role','check_email_domain','update_updated_at')
 ORDER BY proname;

\echo '=== Policies (esperado: 10) ==='
SELECT tablename, policyname FROM pg_policies
 WHERE schemaname='public' ORDER BY tablename, policyname;

\echo '=== Triggers (esperado: 3) ==='
SELECT tgname FROM pg_trigger
 WHERE tgname IN ('on_auth_user_created_assign_role','enforce_email_domain','inventory_updated_at')
 ORDER BY tgname;

\echo '=== Usuarios e roles ==='
SELECT u.email, ur.role
  FROM auth.users u LEFT JOIN user_roles ur ON ur.user_id = u.id
 ORDER BY u.email;
