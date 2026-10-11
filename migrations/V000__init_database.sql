-- ============================================================
-- VIGIA VISION SYSTEMS
-- V000__init_database.sql
-- PostgreSQL 16+
--
-- Inicializacion de la sesion de migraciones.
-- La base de datos debe existir previamente y haber sido creada con UTF8.
--
-- Contenido:
--   - Extension pgcrypto.
--   - Validacion de codificacion UTF8.
--   - Ajustes de sesion para despliegue.
--
-- No crea tablas ni datos de negocio.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

SET client_encoding TO 'UTF8';
SET TIME ZONE 'UTC';
SET search_path TO public;

DO $$
BEGIN
    IF current_setting('server_encoding') <> 'UTF8' THEN
        RAISE EXCEPTION
            'VIGIA requiere codificacion UTF8. Codificacion actual: %',
            current_setting('server_encoding');
    END IF;
END;
$$;

-- ============================================================
-- FIN DE V000__init_database.sql
-- ============================================================
