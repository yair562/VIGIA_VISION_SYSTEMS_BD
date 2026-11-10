-- =============================================================================
-- VIGIA VISION SYSTEMS
-- V003__seed_data.sql
-- PostgreSQL 16+
--
-- Datos iniciales unificados de desarrollo y testing (BD-REVIEW-02).
-- Fuente canónica única para catálogos y usuarios de desarrollo.
--
-- Credenciales de prueba incluidas (Hashes Argon2id PHC generados con PyNaCl):
--   1. admin_dev   / AdminDev2026!   (Rol en BD: ADMINISTRADOR -> Rol funcional: ADMINISTRADOR)
--   2. guardia_dev / GuardiaDev2026! (Rol en BD: OPERADOR      -> Rol funcional: GUARDIA)
--
-- Invariantes y garantías:
--   - Exclusivamente dos usuarios de desarrollo aprobados: admin_dev y guardia_dev.
--   - Mapeo relacional: OPERADOR en base de datos se proyecta como GUARDIA en API.
--   - Ninguna contraseña en texto plano en la base de datos.
--   - Idempotencia total: ON CONFLICT DO NOTHING evita duplicados y no sobreescribe
--     contraseñas modificadas por usuarios.
--   - No incluye cámaras, áreas de visión ni dispositivos móviles sintéticos.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. CATALOGO DE CARRERAS INSTITUCIONALES (IDEMPOTENTE)
-- -----------------------------------------------------------------------------
INSERT INTO carrera (clave, nombre, edificio) VALUES
    ('IC',  'Ingeniería Civil',                       'I'),
    ('ISC', 'Ingeniería en Sistemas Computacionales', 'J'),
    ('II',  'Ingeniería Industrial',                 NULL),
    ('IM',  'Ingeniería en Mecatrónica',              'H'),
    ('LB',  'Licenciatura en Biología',               'A'),
    ('LA',  'Licenciatura en Administración',         'F'),
    ('LG',  'Licenciatura en Gastronomía',            'G')
ON CONFLICT (clave) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. USUARIOS SINTETICOS DE PRUEBA (ARGON2ID PHC HASHES)
-- -----------------------------------------------------------------------------
-- admin_dev:   AdminDev2026!   (ADMINISTRADOR)
-- guardia_dev: GuardiaDev2026! (OPERADOR -> GUARDIA en capa de aplicacion)

INSERT INTO usuario (id_usuario, username, contrasena_hash, nombre_completo, rol, activo) VALUES
    (
        '00000000-0000-0000-0002-000000000001',
      
        'admin_dev',
        '$argon2id$v=19$m=65536,t=2,p=1$ciSUjpFFWxcIf7qTfs63IA$ebc8pWfiNF/MsZ2OBZWopDfBQcHaYGP2KMWBNx5V/tE',
        'Administrador Desarrollo',
        'ADMINISTRADOR',
        TRUE
    ),
    (
        '00000000-0000-0000-0002-000000000002',
        'guardia_dev',
        '$argon2id$v=19$m=65536,t=2,p=1$WggLzGMJf8NWK/pfrxcOOA$pJ1nwI10YHtSv1ok/1yz1+Rn1REGyQZJYMwpEtSL8wU',
        'Guardia Caseta Principal',
        'OPERADOR',
        TRUE
    )
ON CONFLICT (LOWER(username)) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. PERSONAS SINTETICAS (20 ALUMNOS)
-- -----------------------------------------------------------------------------
INSERT INTO persona (id_persona, nombre, ap_paterno, ap_materno, activo) VALUES
    ('00000000-0000-0000-0001-000000000001', 'Carlos', 'Mendoza', 'Reyes', TRUE),
    ('00000000-0000-0000-0001-000000000002', 'Sofia', 'Ramirez', 'Castillo', TRUE),
    ('00000000-0000-0000-0001-000000000003', 'Mateo', 'Morales', 'Flores', TRUE),
    ('00000000-0000-0000-0001-000000000004', 'Alejandro', 'Gutierrez', 'Silva', TRUE),
    ('00000000-0000-0000-0001-000000000005', 'Valeria', 'Hernandez', 'Romero', TRUE),
    ('00000000-0000-0000-0001-000000000006', 'Diego', 'Navarro', 'Ortega', TRUE),
    ('00000000-0000-0000-0001-000000000007', 'Camila', 'Torres', 'Vargas', TRUE),
    ('00000000-0000-0000-0001-000000000008', 'Rodrigo', 'Alvarez', 'Santos', TRUE),
    ('00000000-0000-0000-0001-000000000009', 'Natalia', 'Rios', 'Dominguez', TRUE),
    ('00000000-0000-0000-0001-000000000010', 'Fernando', 'Castillo', 'Soto', TRUE),
    ('00000000-0000-0000-0001-000000000011', 'Daniel', 'Vasquez', 'Luna', TRUE),
    ('00000000-0000-0000-0001-000000000012', 'Mariana', 'Herrera', 'Bravo', TRUE),
    ('00000000-0000-0000-0001-000000000013', 'Emiliano', 'Delgado', 'Leon', TRUE),
    ('00000000-0000-0000-0001-000000000014', 'Paulina', 'Cruz', 'Ibarra', TRUE),
    ('00000000-0000-0000-0001-000000000015', 'Leonardo', 'Jimenez', 'Lara', TRUE),
    ('00000000-0000-0000-0001-000000000016', 'Andrea', 'Moreno', 'Estrada', TRUE),
    ('00000000-0000-0000-0001-000000000017', 'Sebastian', 'Ortiz', 'Aguilar', TRUE),
    ('00000000-0000-0000-0001-000000000018', 'Daniela', 'Campos', 'Ruiz', TRUE),
    ('00000000-0000-0000-0001-000000000019', 'Gabriel', 'Fuentes', 'Pena', TRUE),
    ('00000000-0000-0000-0001-000000000020', 'Valentina', 'Ramos', 'Solis', TRUE)
ON CONFLICT (id_persona) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. ALUMNOS SINTETICOS (DISTRIBUIDOS EN LAS 7 CARRERAS)
-- -----------------------------------------------------------------------------
INSERT INTO alumno (id_persona, matricula, id_carrera, semestre, grupo) VALUES
    -- Ingenieria Civil (IC)
    ('00000000-0000-0000-0001-000000000001', '22100001', (SELECT id_carrera FROM carrera WHERE clave = 'IC'), 8, 'A'),
    ('00000000-0000-0000-0001-000000000002', '23100002', (SELECT id_carrera FROM carrera WHERE clave = 'IC'), 6, 'B'),
    ('00000000-0000-0000-0001-000000000003', '25100003', (SELECT id_carrera FROM carrera WHERE clave = 'IC'), 2, 'A'),
    -- Ingenieria en Sistemas Computacionales (ISC)
    ('00000000-0000-0000-0001-000000000004', '22100004', (SELECT id_carrera FROM carrera WHERE clave = 'ISC'), 8, 'A'),
    ('00000000-0000-0000-0001-000000000005', '23100005', (SELECT id_carrera FROM carrera WHERE clave = 'ISC'), 6, 'A'),
    ('00000000-0000-0000-0001-000000000006', '24100006', (SELECT id_carrera FROM carrera WHERE clave = 'ISC'), 4, 'B'),
    ('00000000-0000-0000-0001-000000000007', '26100007', (SELECT id_carrera FROM carrera WHERE clave = 'ISC'), 1, 'A'),
    -- Ingenieria Industrial (II)
    ('00000000-0000-0000-0001-000000000008', '22100008', (SELECT id_carrera FROM carrera WHERE clave = 'II'), 8, 'A'),
    ('00000000-0000-0000-0001-000000000009', '23100009', (SELECT id_carrera FROM carrera WHERE clave = 'II'), 5, 'B'),
    ('00000000-0000-0000-0001-000000000010', '25100010', (SELECT id_carrera FROM carrera WHERE clave = 'II'), 3, 'A'),
    -- Ingenieria en Mecatronica (IM)
    ('00000000-0000-0000-0001-000000000011', '23100011', (SELECT id_carrera FROM carrera WHERE clave = 'IM'), 6, 'A'),
    ('00000000-0000-0000-0001-000000000012', '24100012', (SELECT id_carrera FROM carrera WHERE clave = 'IM'), 4, 'B'),
    ('00000000-0000-0000-0001-000000000013', '25100013', (SELECT id_carrera FROM carrera WHERE clave = 'IM'), 2, 'A'),
    -- Licenciatura en Biologia (LB)
    ('00000000-0000-0000-0001-000000000014', '22100014', (SELECT id_carrera FROM carrera WHERE clave = 'LB'), 7, 'A'),
    ('00000000-0000-0000-0001-000000000015', '24100015', (SELECT id_carrera FROM carrera WHERE clave = 'LB'), 3, 'A'),
    -- Licenciatura en Administracion (LA)
    ('00000000-0000-0000-0001-000000000016', '22100016', (SELECT id_carrera FROM carrera WHERE clave = 'LA'), 8, 'A'),
    ('00000000-0000-0000-0001-000000000017', '23100017', (SELECT id_carrera FROM carrera WHERE clave = 'LA'), 5, 'B'),
    ('00000000-0000-0000-0001-000000000018', '25100018', (SELECT id_carrera FROM carrera WHERE clave = 'LA'), 2, 'A'),
    -- Licenciatura en Gastronomia (LG)
    ('00000000-0000-0000-0001-000000000019', '23100019', (SELECT id_carrera FROM carrera WHERE clave = 'LG'), 6, 'A'),
    ('00000000-0000-0000-0001-000000000020', '24100020', (SELECT id_carrera FROM carrera WHERE clave = 'LG'), 4, 'A')
ON CONFLICT (matricula) DO NOTHING;

COMMIT;
