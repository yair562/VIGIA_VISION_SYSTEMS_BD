-- ============================================================
-- VIGIA VISION SYSTEMS
-- V001__baseline_v1.sql  (revisado)
-- PostgreSQL 16+
--
-- Modelo inicial: 15 tablas
-- Sin DROP TABLE ni operaciones destructivas.
--
-- IMPORTANTE:
-- Ejecutar únicamente en una base nueva o después de verificar
-- que los objetos no existen. Esta migración no es idempotente.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- 1. PERSONA
-- ============================================================

CREATE TABLE persona (
    id_persona UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    ap_paterno VARCHAR(100) NOT NULL,
    ap_materno VARCHAR(100),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_persona_nombre
        CHECK (nombre = BTRIM(nombre) AND nombre <> ''),
    CONSTRAINT ck_persona_ap_paterno
        CHECK (ap_paterno = BTRIM(ap_paterno) AND ap_paterno <> ''),
    CONSTRAINT ck_persona_ap_materno
        CHECK (
            ap_materno IS NULL
            OR (ap_materno = BTRIM(ap_materno) AND ap_materno <> '')
        )
);

COMMENT ON TABLE persona IS
'Entidad base para personas registradas en VIGIA.';


-- ============================================================
-- 2. CARRERA
-- ============================================================

CREATE TABLE carrera (
    id_carrera UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clave VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(120) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_carrera_clave
        CHECK (clave = BTRIM(clave) AND clave <> ''),
    CONSTRAINT ck_carrera_nombre
        CHECK (nombre = BTRIM(nombre) AND nombre <> '')
);

COMMENT ON TABLE carrera IS
'Catálogo de carreras institucionales.';


-- ============================================================
-- 3. ALUMNO
-- ============================================================

CREATE TABLE alumno (
    id_persona UUID PRIMARY KEY,
    matricula VARCHAR(20) NOT NULL UNIQUE,
    id_carrera UUID NOT NULL,
    semestre SMALLINT NOT NULL,
    grupo VARCHAR(20),

    CONSTRAINT fk_alumno_persona
        FOREIGN KEY (id_persona)
        REFERENCES persona(id_persona) ON DELETE RESTRICT,
    CONSTRAINT fk_alumno_carrera
        FOREIGN KEY (id_carrera)
        REFERENCES carrera(id_carrera) ON DELETE RESTRICT,
    CONSTRAINT ck_alumno_matricula
        CHECK (matricula = BTRIM(matricula) AND matricula <> ''),
    CONSTRAINT ck_alumno_semestre
        CHECK (semestre BETWEEN 1 AND 12),
    CONSTRAINT ck_alumno_grupo
        CHECK (
            grupo IS NULL
            OR (grupo = BTRIM(grupo) AND grupo <> '')
        )
);

CREATE INDEX idx_alumno_carrera
    ON alumno (id_carrera);

COMMENT ON TABLE alumno IS
'Datos académicos específicos de las personas que son alumnos.';


-- ============================================================
-- 4. ADMINISTRATIVO
-- ============================================================

CREATE TABLE administrativo (
    id_persona UUID PRIMARY KEY,
    num_empleado VARCHAR(20) NOT NULL UNIQUE,
    departamento VARCHAR(100),

    CONSTRAINT fk_administrativo_persona
        FOREIGN KEY (id_persona)
        REFERENCES persona(id_persona) ON DELETE RESTRICT,
    CONSTRAINT ck_administrativo_num_empleado
        CHECK (num_empleado = BTRIM(num_empleado) AND num_empleado <> ''),
    CONSTRAINT ck_administrativo_departamento
        CHECK (
            departamento IS NULL
            OR (departamento = BTRIM(departamento) AND departamento <> '')
        )
);

COMMENT ON TABLE administrativo IS
'Datos laborales específicos del personal administrativo.';


-- ============================================================
-- 5. VEHICULO
-- ============================================================

CREATE TABLE vehiculo (
    id_vehiculo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    placa VARCHAR(20) NOT NULL UNIQUE,
    tipo_vehiculo VARCHAR(20) NOT NULL,
    marca VARCHAR(60),
    modelo VARCHAR(60),
    color VARCHAR(40),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_vehiculo_placa
        CHECK (
            placa = UPPER(BTRIM(placa))
            AND placa !~ '[[:space:]-]'
            AND placa <> ''
        ),
    CONSTRAINT ck_vehiculo_tipo
        CHECK (
            tipo_vehiculo IN (
                'AUTOMOVIL',
                'CAMIONETA',
                'CAMION',
                'MOTOCICLETA'
            )
        ),
    CONSTRAINT ck_vehiculo_marca
        CHECK (marca IS NULL OR (marca = BTRIM(marca) AND marca <> '')),
    CONSTRAINT ck_vehiculo_modelo
        CHECK (modelo IS NULL OR (modelo = BTRIM(modelo) AND modelo <> '')),
    CONSTRAINT ck_vehiculo_color
        CHECK (color IS NULL OR (color = BTRIM(color) AND color <> ''))
);

COMMENT ON TABLE vehiculo IS
'Vehículos con matrículas normalizadas: mayúsculas, sin espacios ni guiones.';

COMMENT ON COLUMN vehiculo.placa IS
'Valor normalizado por la aplicación antes de su almacenamiento.';


-- ============================================================
-- 6. PERSONA_VEHICULO
-- ============================================================

CREATE TABLE persona_vehiculo (
    id_persona_vehiculo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_persona UUID NOT NULL,
    id_vehiculo UUID NOT NULL,
    tipo_relacion VARCHAR(25) NOT NULL,
    autorizado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_alta TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_baja TIMESTAMPTZ,

    CONSTRAINT fk_persona_vehiculo_persona
        FOREIGN KEY (id_persona)
        REFERENCES persona(id_persona) ON DELETE RESTRICT,
    CONSTRAINT fk_persona_vehiculo_vehiculo
        FOREIGN KEY (id_vehiculo)
        REFERENCES vehiculo(id_vehiculo) ON DELETE RESTRICT,
    CONSTRAINT ck_persona_vehiculo_tipo_relacion
        CHECK (
            tipo_relacion IN (
                'PROPIETARIO',
                'FAMILIAR',
                'USUARIO_AUTORIZADO'
            )
        ),
    CONSTRAINT ck_persona_vehiculo_fechas
        CHECK (fecha_baja IS NULL OR fecha_baja > fecha_alta)
);

CREATE UNIQUE INDEX uq_persona_vehiculo_vigente
    ON persona_vehiculo (id_persona, id_vehiculo)
    WHERE fecha_baja IS NULL;

CREATE INDEX idx_persona_vehiculo_vehiculo_vigente
    ON persona_vehiculo (id_vehiculo)
    WHERE fecha_baja IS NULL;

CREATE INDEX idx_persona_vehiculo_persona
    ON persona_vehiculo (id_persona);

COMMENT ON TABLE persona_vehiculo IS
'Relación histórica entre personas y vehículos, incluyendo autorización y vigencia.';


-- ============================================================
-- 7. USUARIO
-- ============================================================

CREATE TABLE usuario (
    id_usuario UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) NOT NULL,
    contrasena_hash TEXT NOT NULL,
    nombre_completo VARCHAR(150) NOT NULL,
    rol VARCHAR(20) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_usuario_username
        CHECK (username = BTRIM(username) AND username <> ''),
    CONSTRAINT ck_usuario_hash
        CHECK (contrasena_hash = BTRIM(contrasena_hash) AND contrasena_hash <> ''),
    CONSTRAINT ck_usuario_nombre
        CHECK (nombre_completo = BTRIM(nombre_completo) AND nombre_completo <> ''),
    CONSTRAINT ck_usuario_rol
        CHECK (rol IN ('ADMINISTRADOR', 'OPERADOR', 'AUDITOR'))
);

CREATE UNIQUE INDEX uq_usuario_username_lower
    ON usuario (LOWER(username));

COMMENT ON TABLE usuario IS
'Usuarios que operan y administran el sistema VIGIA.';

COMMENT ON COLUMN usuario.contrasena_hash IS
'Almacena exclusivamente un hash seguro, nunca la contraseña en texto plano. El formato (bcrypt/argon2) es responsabilidad de la aplicación.';


-- ============================================================
-- 8. CAMARA
-- ============================================================

CREATE TABLE camara (
    id_camara UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo VARCHAR(30) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    uri_stream TEXT NOT NULL,
    resolucion_ancho INTEGER,
    resolucion_alto INTEGER,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_camara_codigo
        CHECK (codigo = BTRIM(codigo) AND codigo <> ''),
    CONSTRAINT ck_camara_nombre
        CHECK (nombre = BTRIM(nombre) AND nombre <> ''),
    CONSTRAINT ck_camara_uri
        CHECK (uri_stream = BTRIM(uri_stream) AND uri_stream <> ''),
    CONSTRAINT ck_camara_resolucion
        CHECK (
            (
                resolucion_ancho IS NULL
                AND resolucion_alto IS NULL
            )
            OR
            (
                resolucion_ancho IS NOT NULL
                AND resolucion_alto IS NOT NULL
                AND resolucion_ancho > 0
                AND resolucion_alto > 0
            )
        )
);

COMMENT ON TABLE camara IS
'Cámaras que proporcionan imágenes al sistema de visión.';


-- ============================================================
-- 9. AREA_VISION
-- ============================================================

CREATE TABLE area_vision (
    id_area_vision UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_camara UUID NOT NULL,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tipo_movimiento VARCHAR(10) NOT NULL,
    x_min NUMERIC(4,3) NOT NULL,
    y_min NUMERIC(4,3) NOT NULL,
    x_max NUMERIC(4,3) NOT NULL,
    y_max NUMERIC(4,3) NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_area_vision_camara
        FOREIGN KEY (id_camara)
        REFERENCES camara(id_camara) ON DELETE RESTRICT,
    CONSTRAINT uq_area_vision_camara_codigo
        UNIQUE (id_camara, codigo),
    CONSTRAINT ck_area_vision_codigo
        CHECK (codigo = BTRIM(codigo) AND codigo <> ''),
    CONSTRAINT ck_area_vision_nombre
        CHECK (nombre = BTRIM(nombre) AND nombre <> ''),
    CONSTRAINT ck_area_vision_tipo_movimiento
        CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA')),
    CONSTRAINT ck_area_vision_coordenadas
        CHECK (
            x_min >= 0 AND x_min < x_max AND x_max <= 1
            AND
            y_min >= 0 AND y_min < y_max AND y_max <= 1
        )
);

CREATE INDEX idx_area_vision_camara_activa
    ON area_vision (id_camara, activa);

COMMENT ON TABLE area_vision IS
'Áreas rectangulares de interés configuradas por cámara, con coordenadas normalizadas.';


-- ============================================================
-- 10. DETECCION
-- ============================================================

CREATE TABLE deteccion (
    id_deteccion UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_area_vision UUID NOT NULL,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    placa_detectada VARCHAR(20),
    confianza_placa NUMERIC(4,3),
    confianza_vehiculo NUMERIC(4,3),
    tipo_vehiculo_pred VARCHAR(20),
    ruta_evidencia_foto TEXT,

    CONSTRAINT fk_deteccion_area_vision
        FOREIGN KEY (id_area_vision)
        REFERENCES area_vision(id_area_vision) ON DELETE RESTRICT,
    CONSTRAINT ck_deteccion_placa
        CHECK (
            placa_detectada IS NULL
            OR (
                placa_detectada = UPPER(BTRIM(placa_detectada))
                AND placa_detectada !~ '[[:space:]-]'
                AND placa_detectada <> ''
            )
        ),
    CONSTRAINT ck_deteccion_confianza_placa
        CHECK (
            confianza_placa IS NULL
            OR confianza_placa BETWEEN 0 AND 1
        ),
    CONSTRAINT ck_deteccion_confianza_vehiculo
        CHECK (
            confianza_vehiculo IS NULL
            OR confianza_vehiculo BETWEEN 0 AND 1
        ),
    CONSTRAINT ck_deteccion_tipo_vehiculo
        CHECK (
            tipo_vehiculo_pred IS NULL
            OR tipo_vehiculo_pred IN (
                'AUTOMOVIL',
                'CAMIONETA',
                'CAMION',
                'MOTOCICLETA',
                'OTRO'
            )
        ),
    CONSTRAINT ck_deteccion_evidencia
        CHECK (
            ruta_evidencia_foto IS NULL
            OR (
                ruta_evidencia_foto = BTRIM(ruta_evidencia_foto)
                AND ruta_evidencia_foto <> ''
            )
        )
);

CREATE INDEX idx_deteccion_area_fecha
    ON deteccion (id_area_vision, fecha_hora DESC);

CREATE INDEX idx_deteccion_placa
    ON deteccion (placa_detectada)
    WHERE placa_detectada IS NOT NULL;

COMMENT ON TABLE deteccion IS
'Resultados de visión computacional, incluyendo OCR y niveles de confianza.';

COMMENT ON COLUMN deteccion.confianza_placa IS
'Confianza OCR entre 0 y 1. Multiplicar por 100 para expresarla como porcentaje.';

COMMENT ON COLUMN deteccion.confianza_vehiculo IS
'Confianza de detección del vehículo entre 0 y 1; no equivale a confianza OCR.';


-- ============================================================
-- 11. EVENTO_ACCESO
-- ============================================================

CREATE TABLE evento_acceso (
    id_evento_acceso UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_deteccion UUID,
    id_vehiculo UUID,
    id_usuario_operador UUID,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    placa_efectiva VARCHAR(20),
    tipo_movimiento VARCHAR(10) NOT NULL,
    tipo_acceso VARCHAR(25) NOT NULL,
    resultado_acceso VARCHAR(10) NOT NULL,
    motivo_decision VARCHAR(35) NOT NULL,
    observaciones TEXT,

    CONSTRAINT fk_evento_acceso_deteccion
        FOREIGN KEY (id_deteccion)
        REFERENCES deteccion(id_deteccion) ON DELETE RESTRICT,
    CONSTRAINT fk_evento_acceso_vehiculo
        FOREIGN KEY (id_vehiculo)
        REFERENCES vehiculo(id_vehiculo) ON DELETE RESTRICT,
    CONSTRAINT fk_evento_acceso_usuario
        FOREIGN KEY (id_usuario_operador)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,
    CONSTRAINT ck_evento_acceso_placa
        CHECK (
            placa_efectiva IS NULL
            OR (
                placa_efectiva = UPPER(BTRIM(placa_efectiva))
                AND placa_efectiva !~ '[[:space:]-]'
                AND placa_efectiva <> ''
            )
        ),
    CONSTRAINT ck_evento_acceso_movimiento
        CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA')),
    CONSTRAINT ck_evento_acceso_tipo
        CHECK (tipo_acceso IN ('AUTOMATICO', 'MANUAL_SUPERVISADO')),
    CONSTRAINT ck_evento_acceso_resultado
        CHECK (resultado_acceso IN ('PERMITIDO', 'DENEGADO')),
    CONSTRAINT ck_evento_acceso_motivo
        CHECK (
            motivo_decision IN (
                'VEHICULO_AUTORIZADO',
                'VISITA_JUSTIFICADA',
                'PLACA_NO_REGISTRADA',
                'SIN_ASOCIACION_AUTORIZADA',
                'VEHICULO_INACTIVO',
                'PERSONA_INACTIVA',
                'APERTURA_EMERGENCIA',
                'PLACA_ILEGIBLE_MANUAL',
                'TIMEOUT_PASO',
                'OBSTACULO_SENSOR'
            )
        ),
    CONSTRAINT ck_evento_acceso_observaciones
        CHECK (
            observaciones IS NULL
            OR (observaciones = BTRIM(observaciones) AND observaciones <> '')
        ),
    CONSTRAINT ck_evento_acceso_manual_usuario
        CHECK (
            tipo_acceso <> 'MANUAL_SUPERVISADO'
            OR id_usuario_operador IS NOT NULL
        )
);

CREATE INDEX idx_evento_acceso_fecha
    ON evento_acceso (fecha_hora DESC);

CREATE INDEX idx_evento_acceso_vehiculo_fecha
    ON evento_acceso (id_vehiculo, fecha_hora DESC);

CREATE INDEX idx_evento_acceso_resultado_fecha
    ON evento_acceso (resultado_acceso, fecha_hora DESC);

CREATE INDEX idx_evento_acceso_deteccion
    ON evento_acceso (id_deteccion)
    WHERE id_deteccion IS NOT NULL;

CREATE INDEX idx_evento_acceso_usuario
    ON evento_acceso (id_usuario_operador)
    WHERE id_usuario_operador IS NOT NULL;

CREATE INDEX idx_evento_acceso_placa
    ON evento_acceso (placa_efectiva)
    WHERE placa_efectiva IS NOT NULL;

COMMENT ON TABLE evento_acceso IS
'Registro histórico de decisiones de acceso; no prueba por sí solo un cruce físico.';


-- ============================================================
-- 12. ALERTA
-- ============================================================

CREATE TABLE alerta (
    id_alerta UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_evento_acceso UUID,
    id_deteccion UUID,
    id_usuario_atendio UUID,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_alerta VARCHAR(30) NOT NULL,
    prioridad VARCHAR(10) NOT NULL DEFAULT 'MEDIA',
    estado VARCHAR(12) NOT NULL DEFAULT 'PENDIENTE',
    descripcion TEXT NOT NULL,
    fecha_hora_atencion TIMESTAMPTZ,
    notas_resolucion TEXT,

    CONSTRAINT fk_alerta_evento_acceso
        FOREIGN KEY (id_evento_acceso)
        REFERENCES evento_acceso(id_evento_acceso) ON DELETE RESTRICT,
    CONSTRAINT fk_alerta_deteccion
        FOREIGN KEY (id_deteccion)
        REFERENCES deteccion(id_deteccion) ON DELETE RESTRICT,
    CONSTRAINT fk_alerta_usuario_atendio
        FOREIGN KEY (id_usuario_atendio)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,
    CONSTRAINT ck_alerta_tipo
        CHECK (
            tipo_alerta IN (
                'PLACA_ILEGIBLE',
                'ACCESO_NO_AUTORIZADO',
                'TIMEOUT_PASO',
                'OBSTACULO_SENSOR'
            )
        ),
    CONSTRAINT ck_alerta_prioridad
        CHECK (prioridad IN ('BAJA', 'MEDIA', 'ALTA', 'CRITICA')),
    CONSTRAINT ck_alerta_estado
        CHECK (estado IN ('PENDIENTE', 'ATENDIDA', 'DESCARTADA')),
    CONSTRAINT ck_alerta_descripcion
        CHECK (descripcion = BTRIM(descripcion) AND descripcion <> ''),
    CONSTRAINT ck_alerta_notas_resolucion
        CHECK (
            notas_resolucion IS NULL
            OR (notas_resolucion = BTRIM(notas_resolucion) AND notas_resolucion <> '')
        ),
    CONSTRAINT ck_alerta_referencia
        CHECK (
            id_evento_acceso IS NOT NULL
            OR id_deteccion IS NOT NULL
        ),
    CONSTRAINT ck_alerta_atencion_coherente
        CHECK (
            (
                estado = 'ATENDIDA'
                AND fecha_hora_atencion IS NOT NULL
                AND id_usuario_atendio IS NOT NULL
            )
            OR
            (
                estado <> 'ATENDIDA'
                AND fecha_hora_atencion IS NULL
            )
        ),
    CONSTRAINT ck_alerta_atencion_fecha
        CHECK (
            fecha_hora_atencion IS NULL
            OR fecha_hora_atencion >= fecha_hora
        )
);

CREATE INDEX idx_alerta_estado_fecha
    ON alerta (estado, fecha_hora DESC);

CREATE INDEX idx_alerta_prioridad_fecha
    ON alerta (prioridad, fecha_hora DESC);

CREATE INDEX idx_alerta_evento_acceso
    ON alerta (id_evento_acceso)
    WHERE id_evento_acceso IS NOT NULL;

CREATE INDEX idx_alerta_deteccion
    ON alerta (id_deteccion)
    WHERE id_deteccion IS NOT NULL;

CREATE INDEX idx_alerta_usuario_atendio
    ON alerta (id_usuario_atendio)
    WHERE id_usuario_atendio IS NOT NULL;

COMMENT ON TABLE alerta IS
'Alertas operativas que requieren atención o seguimiento.';


-- ============================================================
-- 13. SENSOR
-- ============================================================

CREATE TABLE sensor (
    id_sensor UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tipo_sensor VARCHAR(20) NOT NULL,
    id_camara UUID,
    ubicacion VARCHAR(150),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_sensor_codigo UNIQUE (codigo),
    CONSTRAINT fk_sensor_camara
        FOREIGN KEY (id_camara)
        REFERENCES camara(id_camara) ON DELETE RESTRICT,
    CONSTRAINT ck_sensor_codigo
        CHECK (codigo = BTRIM(codigo) AND codigo <> ''),
    CONSTRAINT ck_sensor_nombre
        CHECK (nombre = BTRIM(nombre) AND nombre <> ''),
    CONSTRAINT ck_sensor_tipo
        CHECK (tipo_sensor IN ('INFRARROJO', 'LUZ')),
    CONSTRAINT ck_sensor_ubicacion
        CHECK (
            ubicacion IS NULL
            OR (ubicacion = BTRIM(ubicacion) AND ubicacion <> '')
        )
);

CREATE INDEX idx_sensor_camara_activo
    ON sensor (id_camara, activo);

COMMENT ON TABLE sensor IS
'Inventario de sensores físicos utilizados por VIGIA.';

COMMENT ON COLUMN sensor.id_camara IS
'Cámara asociada, si corresponde; puede ser NULL para sensores de caseta.';


-- ============================================================
-- 14. EVENTO_SENSOR
-- ============================================================

CREATE TABLE evento_sensor (
    id_evento_sensor UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_sensor UUID NOT NULL,
    id_evento_acceso UUID,
    id_deteccion UUID,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_evento VARCHAR(25) NOT NULL,
    valor NUMERIC(12,3),
    unidad VARCHAR(15),
    descripcion TEXT,

    CONSTRAINT fk_evento_sensor_sensor
        FOREIGN KEY (id_sensor)
        REFERENCES sensor(id_sensor) ON DELETE RESTRICT,
    CONSTRAINT fk_evento_sensor_acceso
        FOREIGN KEY (id_evento_acceso)
        REFERENCES evento_acceso(id_evento_acceso) ON DELETE RESTRICT,
    CONSTRAINT fk_evento_sensor_deteccion
        FOREIGN KEY (id_deteccion)
        REFERENCES deteccion(id_deteccion) ON DELETE RESTRICT,
    CONSTRAINT ck_evento_sensor_tipo
        CHECK (
            tipo_evento IN (
                'PASO_DETECTADO',
                'LECTURA_ILUMINACION',
                'CAMBIO_ILUMINACION',
                'FALLO'
            )
        ),
    CONSTRAINT ck_evento_sensor_unidad
        CHECK (unidad IS NULL OR (unidad = BTRIM(unidad) AND unidad <> '')),
    CONSTRAINT ck_evento_sensor_descripcion
        CHECK (
            descripcion IS NULL
            OR (descripcion = BTRIM(descripcion) AND descripcion <> '')
        ),
    CONSTRAINT ck_evento_sensor_valor
        CHECK (
            (
                tipo_evento IN ('LECTURA_ILUMINACION', 'CAMBIO_ILUMINACION')
                AND valor IS NOT NULL
                AND valor >= 0
                AND unidad IS NOT NULL
            )
            OR
            (
                tipo_evento = 'PASO_DETECTADO'
                AND valor IS NULL
                AND unidad IS NULL
            )
            OR
            (
                tipo_evento = 'FALLO'
            )
        )
);

CREATE INDEX idx_evento_sensor_fecha
    ON evento_sensor (id_sensor, fecha_hora DESC);

CREATE INDEX idx_evento_sensor_acceso
    ON evento_sensor (id_evento_acceso)
    WHERE id_evento_acceso IS NOT NULL;

CREATE INDEX idx_evento_sensor_deteccion
    ON evento_sensor (id_deteccion)
    WHERE id_deteccion IS NOT NULL;

COMMENT ON TABLE evento_sensor IS
'Historial de lecturas relevantes, pasos detectados, cambios de iluminación y fallos.';

COMMENT ON COLUMN evento_sensor.valor IS
'Valor medido o registrado. Para iluminación, usar la unidad real del dispositivo.';

COMMENT ON COLUMN evento_sensor.id_deteccion IS
'Permite relacionar una medición ambiental con una detección OCR para análisis posterior.';


-- ============================================================
-- 15. ACCION_ILUMINACION
-- ============================================================

CREATE TABLE accion_iluminacion (
    id_accion_iluminacion UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_sensor_luz UUID,
    id_deteccion UUID,
    id_usuario UUID,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    origen VARCHAR(15) NOT NULL,
    nivel_objetivo NUMERIC(5,2) NOT NULL,
    nivel_anterior NUMERIC(5,2),
    estado VARCHAR(15) NOT NULL DEFAULT 'SOLICITADA',
    motivo TEXT NOT NULL,
    detalle_resultado TEXT,

    CONSTRAINT fk_accion_iluminacion_sensor
        FOREIGN KEY (id_sensor_luz)
        REFERENCES sensor(id_sensor) ON DELETE RESTRICT,
    CONSTRAINT fk_accion_iluminacion_deteccion
        FOREIGN KEY (id_deteccion)
        REFERENCES deteccion(id_deteccion) ON DELETE RESTRICT,
    CONSTRAINT fk_accion_iluminacion_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario(id_usuario) ON DELETE RESTRICT,

    CONSTRAINT ck_accion_iluminacion_origen
        CHECK (origen IN ('MANUAL', 'AUTOMATICO')),

    CONSTRAINT ck_accion_iluminacion_objetivo
        CHECK (nivel_objetivo BETWEEN 0 AND 100),

    CONSTRAINT ck_accion_iluminacion_anterior
        CHECK (
            nivel_anterior IS NULL
            OR nivel_anterior BETWEEN 0 AND 100
        ),

    CONSTRAINT ck_accion_iluminacion_estado
        CHECK (
            estado IN (
                'SOLICITADA',
                'APLICADA',
                'FALLIDA',
                'CANCELADA'
            )
        ),

    CONSTRAINT ck_accion_iluminacion_motivo
        CHECK (motivo = BTRIM(motivo) AND motivo <> ''),

    CONSTRAINT ck_accion_iluminacion_detalle
        CHECK (
            detalle_resultado IS NULL
            OR (detalle_resultado = BTRIM(detalle_resultado) AND detalle_resultado <> '')
        ),

    CONSTRAINT ck_accion_iluminacion_manual_usuario
        CHECK (origen <> 'MANUAL' OR id_usuario IS NOT NULL)
);

CREATE INDEX idx_accion_iluminacion_fecha
    ON accion_iluminacion (fecha_hora DESC);

CREATE INDEX idx_accion_iluminacion_estado_fecha
    ON accion_iluminacion (estado, fecha_hora DESC);

CREATE INDEX idx_accion_iluminacion_deteccion
    ON accion_iluminacion (id_deteccion)
    WHERE id_deteccion IS NOT NULL;

CREATE INDEX idx_accion_iluminacion_sensor
    ON accion_iluminacion (id_sensor_luz)
    WHERE id_sensor_luz IS NOT NULL;

CREATE INDEX idx_accion_iluminacion_usuario
    ON accion_iluminacion (id_usuario)
    WHERE id_usuario IS NOT NULL;

COMMENT ON TABLE accion_iluminacion IS
'Bitácora de órdenes de ajuste de iluminación y su resultado. No controla hardware por sí misma.';

COMMENT ON COLUMN accion_iluminacion.nivel_objetivo IS
'Nivel objetivo de iluminación del actuador expresado como porcentaje entre 0 y 100.';

COMMENT ON COLUMN accion_iluminacion.nivel_anterior IS
'Nivel anterior conocido del actuador, si está disponible.';

COMMENT ON COLUMN accion_iluminacion.estado IS
'APLICADA indica confirmación del controlador, no solo envío de una orden.';


-- ============================================================
-- FIN DE V001__baseline_v1.sql (revisado)
-- ============================================================

COMMIT;