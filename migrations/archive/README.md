# Archivo Histórico de Migraciones

Este directorio almacena versiones preliminares o borradores de migraciones que han sido retirados del conjunto activo para evitar colisiones de versiones y ambigüedades.

- **`V001__baseline_v1.sql`**: Borrador preliminar de la línea base de 15 tablas. Fue archivado y sustituido oficialmente por `migrations/V001__baseline_schema.sql`, el cual incorpora soporte para la columna `carrera.edificio`, índices foráneos de cobertura y restricciones de verificación adicionales.
