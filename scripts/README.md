# Scripts de operación

- `apply_migrations.ps1`: ejecuta las migraciones activas en orden, registra
  checksums y evita ejecuciones concurrentes.
- `check_connection.ps1`: comprueba la conexión al PostgreSQL de pruebas.
- `provision_admin.ps1`: permanece bloqueado hasta que exista un proveedor
  Argon2id compatible con el backend. No genera bcrypt ni credenciales
  ficticias.

Los scripts no deben imprimir secretos ni recibir contraseñas como argumentos
de procesos.
