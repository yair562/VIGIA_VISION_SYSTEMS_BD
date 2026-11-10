# VIGIA Vision Systems — Base de Datos

Entorno y ciclo de vida de la base de datos PostgreSQL 16+ para VIGIA Vision Systems.

El modelo relacional canónico consta de **15 tablas**, restricciones de integridad referencial, índices de cobertura, comentarios de metadatos y control automatizado de versiones.

---

## 1. Requisitos Previos

- **Docker Desktop** con motor Linux/WSL2 activo (para entorno de pruebas reproducible).
- **PostgreSQL 16+** cliente (`psql`) accesible en el `PATH` de Windows.
- **PowerShell 7** o Windows PowerShell.
- **Python 3.11+** con entorno virtual configurado en `VIGIA_Vision_Systems/.venv`.

> [!IMPORTANT] Separación de Puertos
> - **Puerto `5433`:** Reservado para el contenedor Docker de VIGIA (`vigia-db`), evitando colisionar con cualquier instalación existente.
> - **Puerto `5432`:** Reservado para el servicio local de PostgreSQL instalado en el sistema operativo anfitrión. No modificar ni afectar este servicio.

---

## 2. Configuración Inicial del Entorno

1. Copiar la plantilla de configuración:
   ```powershell
   Copy-Item Software/.env.example Software/.env
   ```
2. Editar `Software/.env` (archivo global unico) y configurar credenciales locales. El archivo `.env` está estrictamente ignorado en `.gitignore`.
3. Iniciar el servicio PostgreSQL con Docker Compose:
   ```powershell
   docker compose -f Software/BD/compose.yaml up -d
   ```
   *El contenedor se inicializa con codificación nativa UTF-8 y expone el puerto `5433` en `localhost` con persistencia en el volumen `vigia_pgdata`.*

---

## 3. Despliegue de Migraciones y Datos

### Paso 1: Verificar conectividad
```powershell
powershell -File Software/BD/scripts/check_connection.ps1
```

### Paso 2: Ejecutar el orquestador de migraciones y datos iniciales (Fuente Canónica)
```powershell
powershell -File Software/BD/scripts/apply_migrations.ps1
```
*Aplica secuencialmente `V000` a `V003` en una única pasada atómica:*
- `V000`: Extensiones del sistema (`pgcrypto`, etc.).
- `V001`: Esquema relacional base (15 tablas, restricciones e índices).
- `V002`: Triggers y funciones de integridad.
- `V003`: **Datos iniciales unificados** (`migrations/V003__seed_data.sql`), que incluye los catálogos de carreras, los 2 usuarios de desarrollo (`admin_dev` y `guardia_dev`) con hashes Argon2id y 20 alumnos de prueba.

*El script crea la tabla `public.schema_version`, calcula checksums SHA-256 y registra cada migración protegida por bloqueos asesores. Es completamente idempotente.*

### Paso 3: Aprovisionamiento operativo de administrador (Solo Producción Limpia)
Para entornos de producción limpios donde se requiera un administrador operacional independiente:
```powershell
$env:PYTHONPATH = "Software/VIGIA_Vision_Systems"
python Software/BD/scripts/provision_admin.py --username admin --nombre "Administrador General" --rol ADMINISTRADOR
```

---

## 4. Credenciales de Desarrollo (Unificadas en V003)

Tras la ejecución de `apply_migrations.ps1` (o la carga de `V003__seed_data.sql`), quedan disponibles exclusivamente los dos usuarios de desarrollo aprobados:

| Usuario | Contraseña de Prueba | Rol Relacional (BD) | Rol Funcional (API / Dashboard) | Propósito / Alcance |
| :--- | :--- | :--- | :--- | :--- |
| `admin_dev` | `AdminDev2026!` | `ADMINISTRADOR` | `ADMINISTRADOR` | Administración general, gestión de usuarios y cámaras. |
| `guardia_dev` | `GuardiaDev2026!` | `OPERADOR` | `GUARDIA` | Operación de caseta, monitoreo de accesos y supervisión. |

> [!NOTE] Mapeo de Roles RBAC
> El esquema relacional DDL (`V001`) restringe `CHECK (rol IN ('ADMINISTRADOR', 'OPERADOR', 'AUDITOR'))`. En la capa de aplicación (`VIGIA_Core.domain.user.UserDTO`), el rol relacional `OPERADOR` se proyecta como rol funcional `GUARDIA`.

Adicionalmente, `V003__seed_data.sql` inserta 20 alumnos de prueba distribuidos en las 7 carreras institucionales (`IC`, `ISC`, `II`, `IM`, `LB`, `LA`, `LG`), con matrículas y semestres válidos. **No contiene cámaras ni dispositivos móviles sintéticos.**

> [!TIP] Compatibilidad de `seed_data.sql`
> El archivo `Software/BD/seed_data.sql` en la raíz se mantiene exclusivamente como un wrapper de compatibilidad que redirige a `migrations/V003__seed_data.sql` mediante `\ir`. La fuente canónica única es `migrations/V003__seed_data.sql`.

---

## 5. Verificación de Usuarios en PostgreSQL

Para comprobar directamente los usuarios persistidos en PostgreSQL sin mostrar hashes completos:
```powershell
$env:PYTHONPATH = "Software/VIGIA_Vision_Systems"
Software/VIGIA_Vision_Systems/.venv/Scripts/python.exe -c "
from VIGIA_Core.repository.user_repository import resolve_database_dsn
import psycopg2

conn = psycopg2.connect(resolve_database_dsn())
cur = conn.cursor()
cur.execute('SELECT username, rol, activo, SUBSTRING(contrasena_hash FROM 1 FOR 30) || ''...'' FROM usuario ORDER BY username;')
for row in cur.fetchall():
    print(row)
conn.close()
"
```

---

## 6. Ejecución de la API y el Dashboard

### Iniciar Backend API (`VIGIA_API`)
```powershell
$env:PYTHONPATH = "Software/VIGIA_Vision_Systems"
$env:VIGIA_ALLOW_IN_MEMORY = "0"
Software/VIGIA_Vision_Systems/.venv/Scripts/python.exe -m flask --app VIGIA_API.ingest_service:create_ingest_app run --port 5000
```
*Expone el servicio HTTP en `http://localhost:5000` conectado a PostgreSQL en el puerto `5433`.*

### Iniciar Frontend Dashboard (`VIGIA_Dashboard`)
El backend sirve los activos del Dashboard directamente en:
- `http://localhost:5000/app` (Interfaz web principal)
- `http://localhost:5000/api/v1/auth/login` (Autenticación con cookie `HttpOnly`)

---

## 7. Reconstrucción Limpia del Entorno desde Cero

Para reiniciar completamente el entorno de desarrollo y eliminar cualquier dato residual:

```powershell
# 1. Detener el contenedor y eliminar su volumen de datos asociado
docker compose -f Software/BD/compose.yaml down -v

# 2. Levantar el servicio PostgreSQL con volumen limpio
docker compose -f Software/BD/compose.yaml up -d

# 3. Esperar que PostgreSQL esté listo y verificar conectividad
powershell -File Software/BD/scripts/check_connection.ps1

# 4. Aplicar las migraciones ordenadas (V000 a V003, incluyendo datos iniciales unificados)
powershell -File Software/BD/scripts/apply_migrations.ps1
```
*Al finalizar el paso 4, la base de datos queda 100% inicializada con el esquema relacional, catálogos y los usuarios de desarrollo `admin_dev` y `guardia_dev`.*

---

## 8. Estructura del Repositorio

- **`compose.yaml`**: Definición del contenedor `postgres:16-alpine` en puerto `5433`.
- **`seed_data.sql`**: Wrapper de conveniencia hacia `migrations/V003__seed_data.sql`.
- **`migrations/`**: Migraciones SQL versionadas (`V000` a `V003`).
  - `V003__seed_data.sql`: **Fuente canónica unificada** de datos iniciales y usuarios de desarrollo.
  - **`archive/`**: Versiones preliminares archivadas fuera de la ruta de ejecución.
- **`scripts/`**:
  - `apply_migrations.ps1`: Orquestador transaccional con control de versiones e idempotencia.
  - `check_connection.ps1`: Diagnóstico de conectividad con `psql`.
  - `provision_admin.py`: Herramienta CLI de aprovisionamiento de administrador con Argon2id.
  - `provision_admin.ps1`: Wrapper en PowerShell para aprovisionamiento seguro.
- **`tests/`**: Pruebas de integridad del esquema relacional y codificación UTF-8.
- **`docs/`**: Documentación técnica y modelo relacional.

---

## 9. Control de Fallos y Diagnóstico

- **Parada inmediata ante errores:** Cualquier sentencia SQL errónea aborta la transacción (`ON_ERROR_STOP=1`) y el script retorna código de salida `1`.
- **Detección de alteración de migraciones:** Si una migración ya aplicada sufre modificaciones en su archivo fuente, el orquestador aborta por discrepancia de checksum SHA-256.
- **Detener el contenedor:**
  ```powershell
  docker compose -f Software/BD/compose.yaml stop
  ```
- **Eliminar contenedor preservando datos del volumen:**
  ```powershell
  docker compose -f Software/BD/compose.yaml down
  ```
