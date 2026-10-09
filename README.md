# VIGIA — Base de Datos

## Propósito

Este repositorio organizará los artefactos específicos de la base de datos de
VIGIA Vision Systems. Su objetivo es proporcionar una ubicación independiente
para la documentación, las futuras migraciones, las utilidades operativas y
las pruebas del esquema.

El esquema PostgreSQL V2 vigente de trabajo se incorporará en una etapa
posterior. Los documentos antiguos de base de datos que puedan existir en la
aplicación no son la fuente oficial del esquema actual.

## Relación con VIGIA Vision Systems

Este proyecto complementa la aplicación ubicada en `Software/VIGIA_Vision_Systems/`
y mantiene separada su evolución de base de datos. No contiene ni modifica el
código de la aplicación.

## Tecnología prevista

- PostgreSQL como sistema gestor de base de datos.
- Docker Compose como tecnología prevista para facilitar entornos locales y
  operaciones reproducibles.

La configuración de Docker, los archivos de entorno y los procedimientos
ejecutables se definirán en una etapa posterior.

## Organización de directorios

- `docs/`: documentación técnica, decisiones de diseño y procedimientos de
  despliegue.
- `migrations/`: migraciones SQL versionadas e incrementales del esquema
  PostgreSQL.
- `scripts/`: utilidades controladas para operaciones de la base de datos,
  respaldos y restauración.
- `tests/`: pruebas de integridad referencial, restricciones, índices y
  comportamiento del esquema.

Cada directorio contiene un README que delimita su uso y los artefactos que
podrá contener.

## Convenciones generales

- Mantener los nombres de directorios en minúsculas.
- Versionar los cambios de esquema de forma incremental y trazable.
- No inventar tablas, relaciones ni reglas de negocio fuera del DDL vigente.
- Mantener la documentación y los archivos necesarios para reproducir el
  proyecto bajo control de versiones.
- Excluir secretos, archivos temporales, respaldos locales y archivos
  generados por herramientas.

## Estado actual

La estructura inicial del proyecto está preparada. El despliegue todavía no
ha iniciado y aún no se han incorporado el esquema SQL, las migraciones
ejecutables, los scripts operativos ni las configuraciones de despliegue.
