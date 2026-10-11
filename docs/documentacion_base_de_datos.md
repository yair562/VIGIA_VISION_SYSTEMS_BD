# Documentación técnica de la base de datos

## 1. Propósito y alcance

La base de datos de VIGIA Vision Systems registra personas, vehículos,
configuración de cámaras y áreas de visión, detecciones, decisiones de acceso,
alertas, sensores y acciones de iluminación. Es la persistencia relacional de
la versión 1; no ejecuta el procesamiento de vídeo, OCR, autorización de
aplicación ni control físico de dispositivos.

## 2. Tecnología y despliegue

- PostgreSQL 16 (`postgres:16-alpine` en [`compose.yaml`](../compose.yaml)).
- Servicio Docker expuesto en `127.0.0.1:5433`.
- Datos persistidos en el volumen definido por Compose.
- Base creada previamente con codificación UTF-8.
- `V000` establece UTF-8 para la sesión y zona horaria UTC.
- El puerto 5432 del PostgreSQL local no forma parte de este entorno.

No se incluyen credenciales, contraseñas ni valores de `.env`.

## 3. Responsabilidad de las migraciones

| Versión | Responsabilidad real |
|---|---|
| `V000__init_database.sql` | Habilita `pgcrypto`, establece `client_encoding=UTF8`, UTC y `search_path=public`, y valida `server_encoding`. No crea tablas de negocio. |
| `V001__baseline_schema.sql` | Crea las 15 tablas, PK, 20 FK, `CHECK`, índices y comentarios del modelo. |
| `V002__triggers.sql` | No-op documental. No crea funciones ni triggers porque V1 usa integridad declarativa. |
| `V003__seed_data.sql` | Inserta siete carreras con `ON CONFLICT (clave) DO NOTHING`. No inserta usuarios administradores. |

La variante histórica `migrations/archive/V001__baseline_v1.sql` está fuera de
la secuencia activa y no debe ejecutarse.

## 4. Orden y procedimiento

El ejecutor [`scripts/apply_migrations.ps1`](../scripts/apply_migrations.ps1)
descubre los archivos activos, los ordena numéricamente y registra SHA-256 en
`public.schema_version`. Ejecuta cada archivo con `ON_ERROR_STOP=1`, usa
transacciones, un mutex local y un bloqueo transaccional de PostgreSQL.

Procedimiento documentado:

1. Copiar `.env.example` a `.env` y completar la configuración local sin
   versionar `.env`.
2. Iniciar el servicio con `docker compose up -d`.
3. Ejecutar [`scripts/check_connection.ps1`](../scripts/check_connection.ps1).
4. Ejecutar `scripts/apply_migrations.ps1`.
5. Ejecutar [`tests/V001__integrity_checks.sql`](../tests/V001__integrity_checks.sql).

Una segunda ejecución omite versiones con checksum y nombre coincidentes. No
se deben editar migraciones ya registradas ni adoptar automáticamente una base
con tablas de negocio sin historial.

## 5. Evidencia de pruebas

La prueba aislada documentada durante la estabilización del runner ejecutó
V000–V003 desde una base temporal y verificó 15 tablas, 20 FK, siete carreras,
UTF-8, `schema_version` y una segunda ejecución sin duplicados. También se
verificaron los checksums históricos de `vigia_db` contra los archivos activos.

La prueba de integridad disponible comprueba esos objetos y datos mediante
[`tests/V001__integrity_checks.sql`](../tests/V001__integrity_checks.sql).
Esta documentación no afirma una nueva ejecución en la fecha de este
documento: los resultados anteriores son la evidencia registrada del
procedimiento.

## 6. Decisiones de diseño

- La integridad crítica está en PostgreSQL mediante FK, `CHECK`, `UNIQUE` e
  índices; V002 no introduce lógica oculta en triggers.
- `vehiculo.placa` es el registro institucional.
- `deteccion.placa_detectada` conserva la evidencia original, incluso si es
  ilegible o incorrecta.
- `evento_acceso.placa_efectiva` representa la placa usada en la decisión y no
  tiene que coincidir con el vehículo asociado.
- Una placa corregida no sobrescribe la detección original. La V1 no guarda
  todavía actor, motivo ni historial de cada corrección.
- La autorización de acceso permanece separada de la detección visual.
- Los datos iniciales se limitan al catálogo institucional; el administrador
  requiere un aprovisionamiento Argon2id compatible con la aplicación.

## 7. Estado y limitaciones conocidas

Implementado: esquema relacional, migraciones V000–V003, catálogo de carreras,
runner con checksums e idempotencia, prueba de integridad y documentación del
modelo.

No implementado: motor de visión, captura de fotogramas, OCR, APIs, integración
con aplicación, triggers de negocio, historial de correcciones y
aprovisionamiento efectivo del administrador.

Los cambios que requieran nuevas columnas, auditoría de correcciones o
metadatos de procesamiento deben llegar como migraciones posteriores. No se
modifican V000–V003 por esas necesidades.
