\set ON_ERROR_STOP on
\echo 'Verificando la integridad del despliegue de VIGIA (15 tablas, codificación, semillas y versiones)...'

DO $$
DECLARE
    expected text[] := ARRAY[
        'persona', 'carrera', 'alumno', 'administrativo', 'vehiculo',
        'persona_vehiculo', 'usuario', 'camara', 'area_vision', 'deteccion',
        'evento_acceso', 'alerta', 'sensor', 'evento_sensor',
        'accion_iluminacion'
    ];
    actual text[];
    table_count integer;
    foreign_key_count integer;
    carrera_count integer;
    accented_name text;
    v_schema_versions text[];
BEGIN
    -- 1. Verificación de 15 tablas en public
    SELECT count(*) INTO table_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND c.relname = ANY(expected);
    IF table_count <> cardinality(expected) THEN
        RAISE EXCEPTION 'Se esperaban 15 tablas y se encontraron %', table_count;
    END IF;

    SELECT array_agg(name ORDER BY name) INTO actual
    FROM unnest(expected) AS name
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = name AND c.relkind = 'r'
    );
    IF actual IS NOT NULL THEN
        RAISE EXCEPTION 'Faltan tablas del modelo: %', actual;
    END IF;

    -- 2. Verificación de claves foráneas mínimas
    SELECT count(*) INTO foreign_key_count
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND con.contype = 'f';
    IF foreign_key_count <> 20 THEN
        RAISE EXCEPTION 'Se esperaban 20 claves foráneas y se encontraron %', foreign_key_count;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_alumno_persona') THEN
        RAISE EXCEPTION 'Falta fk_alumno_persona';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_evento_acceso_deteccion') THEN
        RAISE EXCEPTION 'Falta fk_evento_acceso_deteccion';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_alerta_evento_acceso') THEN
        RAISE EXCEPTION 'Falta fk_alerta_evento_acceso';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_accion_iluminacion_objetivo') THEN
        RAISE EXCEPTION 'Falta ck_accion_iluminacion_objetivo';
    END IF;

    -- 3. Verificación de columna edificio en carrera
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'carrera' AND column_name = 'edificio'
    ) THEN
        RAISE EXCEPTION 'Falta la columna edificio en tabla carrera';
    END IF;

    -- 4. Verificación de catálogo institucional de carreras y caracteres UTF-8
    SELECT count(*) INTO carrera_count FROM public.carrera;
    IF carrera_count < 7 THEN
        RAISE EXCEPTION 'Se esperaban 7 carreras en catálogo inicial y se encontraron %', carrera_count;
    END IF;

    SELECT nombre INTO accented_name FROM public.carrera WHERE clave = 'ISC';
    IF accented_name <> 'Ingeniería en Sistemas Computacionales' THEN
        RAISE EXCEPTION 'Corrupción de caracteres acentuados en carrera ISC: "%"', accented_name;
    END IF;
    IF accented_name LIKE '%?%' THEN
        RAISE EXCEPTION 'Se detectó sustitución de caracteres Unicode por "?": "%"', accented_name;
    END IF;

    -- 5. Verificación de tabla de control schema_version
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'schema_version'
    ) THEN
        RAISE EXCEPTION 'Falta la tabla de control schema_version';
    END IF;

    SELECT array_agg(version ORDER BY version) INTO v_schema_versions FROM public.schema_version;
    IF v_schema_versions IS DISTINCT FROM ARRAY['V000', 'V001', 'V002', 'V003'] THEN
        RAISE EXCEPTION 'Historial inesperado en schema_version: %', v_schema_versions;
    END IF;
END $$;

SELECT 'OK: Despliegue íntegro verificado (15 tablas, FKs, restricciones, UTF-8 y schema_version).' AS resultado;