-- ============================================================================
-- VIGÍA VISION SYSTEMS
-- V004__enrolamiento_camaras_qr.sql
-- PostgreSQL 16+
--
-- Descripción:
--   Soporte relacional para el enrolamiento de dispositivos móviles mediante
--   códigos QR y la gestión de credenciales individuales de transmisión
--   por cámara lógica (CAM-ENTRADA / CAM-SALIDA).
--   Basado en la especificación técnica aprobada ENR-02B-D (Revisión R1).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLA: camera_pairing_request
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS camera_pairing_request (
    id_solicitud UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_camara UUID NOT NULL,
    token_claim_hash VARCHAR(64) NOT NULL,
    token_poll_hash VARCHAR(64),
    estado VARCHAR(20) NOT NULL DEFAULT 'CREADA',
    dispositivo_info JSONB,
    creado_por UUID NOT NULL,
    resuelto_por UUID,
    motivo_rechazo TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en TIMESTAMPTZ NOT NULL,
    reclamado_en TIMESTAMPTZ,
    resuelto_en TIMESTAMPTZ,
    consumido_en TIMESTAMPTZ,
    cancelado_en TIMESTAMPTZ,

    CONSTRAINT fk_pairing_camara
        FOREIGN KEY (id_camara)
        REFERENCES camara(id_camara) ON DELETE RESTRICT,

    CONSTRAINT fk_pairing_creador
        FOREIGN KEY (creado_por)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,

    CONSTRAINT fk_pairing_resolutor
        FOREIGN KEY (resuelto_por)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,

    CONSTRAINT ck_pairing_estado
        CHECK (estado IN ('CREADA', 'PENDIENTE', 'APROBADA', 'RECHAZADA', 'EXPIRADA', 'CANCELADA', 'CONSUMIDA')),

    CONSTRAINT ck_pairing_claim_hash_format
        CHECK (
            token_claim_hash = BTRIM(token_claim_hash)
            AND length(token_claim_hash) = 64
            AND token_claim_hash ~* '^[a-f0-9]{64}$'
        ),

    CONSTRAINT ck_pairing_poll_hash_format
        CHECK (
            token_poll_hash IS NULL
            OR (
                token_poll_hash = BTRIM(token_poll_hash)
                AND length(token_poll_hash) = 64
                AND token_poll_hash ~* '^[a-f0-9]{64}$'
            )
        ),

    CONSTRAINT ck_pairing_fechas_coherentes
        CHECK (
            expira_en > creado_en
            AND (reclamado_en IS NULL OR reclamado_en >= creado_en)
            AND (resuelto_en IS NULL OR resuelto_en >= creado_en)
            AND (consumido_en IS NULL OR consumido_en >= creado_en)
            AND (cancelado_en IS NULL OR cancelado_en >= creado_en)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pairing_token_claim_hash
    ON camera_pairing_request (token_claim_hash);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pairing_token_poll_hash
    ON camera_pairing_request (token_poll_hash)
    WHERE token_poll_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_pairing_activa_por_camara
    ON camera_pairing_request (id_camara)
    WHERE estado IN ('CREADA', 'PENDIENTE');

CREATE INDEX IF NOT EXISTS idx_pairing_camara_estado
    ON camera_pairing_request (id_camara, estado);

CREATE INDEX IF NOT EXISTS idx_pairing_estado_expira
    ON camera_pairing_request (estado, expira_en);

CREATE INDEX IF NOT EXISTS idx_pairing_dashboard_pendientes
    ON camera_pairing_request (creado_en ASC)
    WHERE estado = 'PENDIENTE';

CREATE INDEX IF NOT EXISTS idx_pairing_creador
    ON camera_pairing_request (creado_por);

COMMENT ON TABLE camera_pairing_request IS
'Registro auditable del ciclo de vida de solicitudes de enrolamiento QR hacia cámaras lógicas.';


-- ----------------------------------------------------------------------------
-- 2. TABLA: camara_credencial
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS camara_credencial (
    id_credencial UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_camara UUID NOT NULL,
    id_solicitud UUID NOT NULL,
    token_transmision_hash VARCHAR(64) NOT NULL,
    clave_cifrado_id VARCHAR(50) NOT NULL DEFAULT 'v1-plain-token',
    credencial_cifrada TEXT,
    intentos_entrega SMALLINT NOT NULL DEFAULT 0,
    entregado_en TIMESTAMPTZ,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    revocado_por UUID,
    motivo_revocacion TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revocado_en TIMESTAMPTZ,

    CONSTRAINT fk_credencial_camara
        FOREIGN KEY (id_camara)
        REFERENCES camara(id_camara) ON DELETE RESTRICT,

    CONSTRAINT fk_credencial_solicitud
        FOREIGN KEY (id_solicitud)
        REFERENCES camera_pairing_request(id_solicitud) ON DELETE RESTRICT,

    CONSTRAINT fk_credencial_revocador
        FOREIGN KEY (revocado_por)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,

    CONSTRAINT ck_credencial_hash_format
        CHECK (
            token_transmision_hash = BTRIM(token_transmision_hash)
            AND length(token_transmision_hash) = 64
            AND token_transmision_hash ~* '^[a-f0-9]{64}$'
        ),

    CONSTRAINT ck_credencial_clave_cifrado_format
        CHECK (
            clave_cifrado_id = BTRIM(clave_cifrado_id)
            AND length(clave_cifrado_id) >= 3
        ),

    CONSTRAINT ck_credencial_intentos
        CHECK (intentos_entrega >= 0 AND intentos_entrega <= 5),

    CONSTRAINT ck_credencial_revocacion_coherente
        CHECK (
            (activa = TRUE AND revocado_en IS NULL AND revocado_por IS NULL)
            OR
            (activa = FALSE AND revocado_en IS NOT NULL)
        ),

    CONSTRAINT ck_credencial_fechas_coherentes
        CHECK (
            activado_en >= creado_en
            AND (revocado_en IS NULL OR revocado_en >= activado_en)
            AND (entregado_en IS NULL OR entregado_en >= creado_en)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_credencial_solicitud
    ON camara_credencial (id_solicitud);

CREATE UNIQUE INDEX IF NOT EXISTS uq_credencial_transmision_hash
    ON camara_credencial (token_transmision_hash);

CREATE UNIQUE INDEX IF NOT EXISTS uq_camara_credencial_activa
    ON camara_credencial (id_camara)
    WHERE activa = TRUE;

CREATE INDEX IF NOT EXISTS idx_credencial_activa_lookup
    ON camara_credencial (token_transmision_hash, id_camara)
    WHERE activa = TRUE;

CREATE INDEX IF NOT EXISTS idx_credencial_historial_camara
    ON camara_credencial (id_camara, creado_en DESC);

COMMENT ON TABLE camara_credencial IS
'Credenciales criptográficas de transmisión autorizadas por cámara lógica para ingesta push.';
