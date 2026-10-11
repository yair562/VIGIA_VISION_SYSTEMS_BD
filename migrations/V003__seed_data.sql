-- ============================================================
-- VIGIA VISION SYSTEMS
-- V003__seed_data.sql
-- PostgreSQL 16+
--
-- Catalogos institucionales iniciales.
-- El usuario administrador se aprovisiona por separado mediante
-- scripts/provision_admin.ps1 cuando exista el proveedor Argon2id
-- compatible con el backend.
--
-- Idempotente: se puede re-ejecutar sin duplicar catalogos.
-- ============================================================

BEGIN;

INSERT INTO carrera (clave, nombre, edificio) VALUES
    ('IC',  'Ingeniería Civil',                       'I'),
    ('ISC', 'Ingeniería en Sistemas Computacionales', 'J'),
    ('II',  'Ingeniería Industrial',                 NULL),
    ('IM',  'Ingeniería en Mecatrónica',              'H'),
    ('LB',  'Licenciatura en Biología',               'A'),
    ('LA',  'Licenciatura en Administración',         'F'),
    ('LG',  'Licenciatura en Gastronomía',            'G')
ON CONFLICT (clave) DO NOTHING;

-- Camara y areas demo son opcionales y deben configurarse con datos reales.

COMMIT;
