# Modelo relacional VIGIA

La migración canónica [`V001__baseline_schema.sql`](../migrations/V001__baseline_schema.sql)
crea las 15 tablas del modelo inicial en el esquema `public`.

## Entidades principales

- `persona` es la entidad base. `alumno` y `administrativo` extienden a una
  persona mediante una clave primaria que también es foránea.
- `carrera` se relaciona con `alumno`.
- `vehiculo` se vincula con personas mediante `persona_vehiculo`.
- `usuario` representa las cuentas operativas y de auditoría.
- `camara` contiene las fuentes de video; `area_vision` define sus zonas de
  entrada o salida.
- `deteccion` registra los resultados de reconocimiento asociados a un área.
- `evento_acceso` registra la decisión de acceso y puede referenciar una
  detección, un vehículo y el usuario que la supervisó.
- `alerta` se relaciona con un evento de acceso o una detección y registra su
  atención.
- `sensor` pertenece a una cámara y `evento_sensor` registra sus lecturas,
  opcionalmente relacionadas con un evento de acceso o una detección.
- `accion_iluminacion` registra órdenes de iluminación asociadas a un sensor,
  una detección y/o el usuario que las originó.

## Integridad

El DDL define claves primarias UUID, claves foráneas, restricciones `CHECK`,
unicidad donde corresponde e índices para consultas por fecha, estado y
relaciones frecuentes. Las reglas de negocio relevantes (por ejemplo, rangos
de confianza, fechas de vigencia y coherencia entre estados) están declaradas
en la migración para que se apliquen en la base de datos.

Para validar el esquema después de aplicar la migración, ejecuta
[`tests/V001__integrity_checks.sql`](../tests/V001__integrity_checks.sql).
