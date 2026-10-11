# VIGIA Vision Systems — Base de Datos

Entorno y ciclo de vida de la base de datos PostgreSQL 16+ para VIGIA Vision Systems.

El modelo relacional canónico consta de **15 tablas**, restricciones de integridad referencial, índices de cobertura, comentarios de metadatos y control automatizado de versiones.

---

## 1. Requisitos Previos

- **Docker Desktop** con motor Linux/WSL2 activo (para entorno de pruebas reproducible).
- **PostgreSQL 16+** cliente (`psql`) accesible en el `PATH` de Windows.
- **PowerShell 7** o Windows PowerShell.

> [!IMPORTANT] Separación de Puertos
> - **Puerto `5433`:** Reservado para el contenedor Docker de VIGIA (`vigia-db`), evitando colisionar con cualquier instalación existente.
> - **Puerto `5432`:** Reservado para el servicio local de PostgreSQL instalado en el sistema operativo anfitrión. No modificar ni afectar este servicio.

---

## 2. Configuración Inicial del Entorno

1. Copiar la plantilla de configuración:
   ```powershell
   Copy-Item .env.example .env
   ```
2. Editar `.env` y configurar una contraseña segura. El archivo `.env` está estrictamente ignorado en `.gitignore`.
3. Iniciar el servicio PostgreSQL con Docker Compose:
   ```powershell
   docker compose up -d
   ```
   *El contenedor se inicializa con codificación nativa UTF-8 y expone el puerto `5433` en `localhost` con persistencia en el volumen `vigia_pgdata`.*

---

## 3. Despliegue de Migraciones y Verificación

### Paso 1: Verificar conectividad
```powershell
.\scripts\check_connection.ps1
```

### Paso 2: Ejecutar el orquestador de migraciones
```powershell
.\scripts\apply_migrations.ps1
```
*El script aplica secuencialmente `V000` a `V003`, crea la tabla `public.schema_version`, calcula checksums SHA-256 de los archivos y registra cada migración de forma atómica y protegida por bloqueos asesores.*

*Si se ejecuta nuevamente, detecta que todas las migraciones ya fueron aplicadas y finaliza sin duplicar tablas ni datos.*

### Paso 3: Aprovisionar el usuario administrador inicial
```powershell
.\scripts\provision_admin.ps1
```
*Actualmente se detiene de forma intencional: el backend accesible todavía no
implementa autenticación ni proporciona un proveedor Argon2id compatible. No
se generan hashes bcrypt ni se almacenan credenciales ficticias.*

El aprovisionamiento podrá habilitarse cuando se confirme la biblioteca y el
contrato de verificación Argon2id del backend. `pgcrypto` no se utiliza para
generar contraseñas.

### Paso 4: Ejecutar pruebas de integridad
```powershell
psql -h localhost -p 5433 -U vigia_admin -d vigia_db -f .\tests\V001__integrity_checks.sql
```
*Comprueba la existencia de las 15 tablas, claves foráneas, restricciones, catálogo institucional de carreras con caracteres acentuados UTF-8 y registro de versiones.*

---

## 4. Estructura del Repositorio

- **`compose.yaml`**: Definición de contenedor `postgres:16-alpine` en puerto `5433`.
- **`migrations/`**: Migraciones SQL versionadas (`V000` a `V003`).
  - **`archive/`**: Versiones preliminares archivadas fuera de la ruta de ejecución.
- **`scripts/`**:
  - `apply_migrations.ps1`: Orquestador transaccional con control de versiones e idempotencia.
  - `check_connection.ps1`: Diagnóstico de conectividad con `psql`.
  - `provision_admin.ps1`: Aprovisionamiento seguro del primer administrador.
- **`tests/`**: Pruebas de integridad del esquema relacional y codificación UTF-8.
- **`docs/`**: Documentación técnica y modelo relacional.

---

## 5. Control de Fallos y Diagnóstico

- **Parada inmediata ante errores:** Cualquier sentencia SQL errónea aborta la transacción (`ON_ERROR_STOP=1`) y el script retorna código de salida `1`.
- **Detección de alteración de migraciones:** Si una migración ya aplicada sufre modificaciones en su archivo fuente, el orquestador aborta por discrepancia de checksum SHA-256.
- **Detener el contenedor:**
  ```powershell
  docker compose stop
  ```
- **Eliminar contenedor preservando datos del volumen:**
  ```powershell
  docker compose down
  ```
