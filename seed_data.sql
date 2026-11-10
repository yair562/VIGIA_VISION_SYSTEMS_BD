-- =============================================================================
-- VIGIA VISION SYSTEMS — SEED DATA (REFERENCIA DE COMPATIBILIDAD)
-- =============================================================================
-- Archivo: Software/BD/seed_data.sql
--
-- NOTA DE ARQUITECTURA (BD-REVIEW-02):
-- La fuente canónica única para la siembra de datos de desarrollo y testing
-- ha sido unificada de forma definitiva en el sistema de migraciones oficial:
--
--   Software/BD/migrations/V003__seed_data.sql
--
-- Toda inicialización mediante Docker o el orquestador apply_migrations.ps1
-- aplica V003 automáticamente. Este archivo se conserva como wrapper
-- de conveniencia para invocar directamente a V003 sin duplicar código SQL.
-- =============================================================================

\ir migrations/V003__seed_data.sql
