# Migraciones — VIGIA Vision Systems

Este directorio contiene las migraciones SQL versionadas e incrementales del esquema de base de datos para PostgreSQL 16+.

---

## 1. Migraciones Activas (Línea Base V1)

Las migraciones se ejecutan en orden estrictamente ascendente:

1. **`V000__init_database.sql`**: Inicialización de la base de datos `vigia_db`.
   - Habilita la extensión `pgcrypto`.
   - Establece la zona horaria predeterminada (`UTC`) y `search_path` (`public`).
   - Valida la codificación del servidor en `UTF8` y configura `client_encoding`.
   - No es destructivo y no crea tablas de negocio.

2. **`V001__baseline_schema.sql`**: Esquema canónico oficial (15 tablas).
   - Crea las entidades institucionales (`persona`, `carrera`, `alumno`, `administrativo`, `vehiculo`, `persona_vehiculo`).
   - Crea las cuentas de software RBAC (`usuario`).
   - Crea las entidades de captura y visión (`camara`, `area_vision`, `deteccion`).
   - Crea la auditoría de accesos e incidentes (`evento_acceso`, `alerta`).
   - Crea los subsistemas de telemetría física (`sensor`, `evento_sensor`, `accion_iluminacion`).
   - Define claves primarias UUID, 20 claves foráneas con `ON DELETE RESTRICT`, restricciones `CHECK`, índices parciales y comentarios.
   - Ejecutable una sola vez sobre una base limpia.

3. **`V002__triggers.sql`**: Reserva técnica documental.
   - En la Línea Base V1 toda la integridad referencial y de dominio se resuelve mediante restricciones declarativas. No realiza cambios de esquema.

4. **`V003__seed_data.sql`**: Catálogos y datos iniciales institucionales.
   - Inserta la oferta educativa institucional (7 carreras con clave, nombre y edificio) de forma idempotente (`ON CONFLICT (clave) DO NOTHING`).
   - La creación del usuario administrador se encuentra desacoplada por seguridad; se realiza mediante `scripts/provision_admin.ps1`.

---

## 2. Directorio Histórico (`archive/`)

- **`archive/V001__baseline_v1.sql`**: Borrador preliminar retirado del conjunto activo para evitar colisiones de versiones y ambigüedad. No es procesado por el ejecutor de migraciones.

---

## 3. Orquestación y Control de Versiones

El despliegue automatizado se realiza con:
```powershell
.\scripts\apply_migrations.ps1
```

Para una base temporal aislada de pruebas puede usarse
`-AllowNonVigiaDatabase` junto con `-Database`; nunca se debe usar esa opción
para saltarse la validación del destino en un despliegue normal.

### Características del Ejecutor:
- **Tabla de control:** Registra cada archivo aplicado en `public.schema_version` (versión, archivo, checksum SHA-256, fecha y duración).
- **Idempotencia:** Detecta migraciones ya aplicadas y las omite de forma segura.
- **Detección de manipulación:** Si un archivo aplicado fue modificado posteriormente, el ejecutor aborta por conflicto de checksum SHA-256.
- **Atomicidad:** Cada migración y su registro en `schema_version` se envían
  juntos mediante un archivo temporal UTF-8 sin BOM y se coordinan dentro de
  la misma transacción.
- **Control de concurrencia:** Usa un mutex con nombre en Windows para evitar
  dos ejecutores locales simultáneos y bloqueos transaccionales de PostgreSQL
  durante cada migración.
- **Manejo de errores:** Cualquier fallo aborta la transacción (`ON_ERROR_STOP=1`), no registra la versión y devuelve un código de salida `1`.

---

## 4. Reglas para Incorporar Nuevas Migraciones

1. Asignar un número correlativo superior estricto: `V004__nombre_descriptivo.sql`.
2. Mantener la codificación estrictamente en **UTF-8 sin BOM**.
3. Escribir sentencias compatibles con PostgreSQL 16+.
4. Nunca modificar ni reescribir migraciones previas que ya hayan sido aplicadas en cualquier entorno.
5. Emplear transacciones explícitas (`BEGIN; ... COMMIT;`).
