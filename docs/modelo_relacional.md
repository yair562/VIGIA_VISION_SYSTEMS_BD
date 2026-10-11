# Modelo relacional de VIGIA

## Alcance

Este documento describe el modelo que realmente crea
[`V001__baseline_schema.sql`](../migrations/V001__baseline_schema.sql) en el
esquema `public`. La línea base contiene 15 tablas, claves UUID generadas con
`pgcrypto`, 20 claves foráneas, restricciones `CHECK`, índices y comentarios.
No describe componentes de aplicación ni tablas futuras.

## Entidades y relaciones

| Entidad | Atributos relevantes | Relaciones |
|---|---|---|
| `persona` | `id_persona`, nombre, apellidos, `activo`, `creado_en` | Entidad base de `alumno`, `administrativo` y `persona_vehiculo`. |
| `carrera` | `id_carrera`, `clave`, nombre, `edificio`, `activo` | Una carrera puede tener varios `alumno`. |
| `alumno` | `id_persona`, `matricula`, `id_carrera`, semestre, grupo | Extiende a `persona`; referencia `carrera`. |
| `administrativo` | `id_persona`, `num_empleado`, departamento | Extiende a `persona`. |
| `vehiculo` | `id_vehiculo`, `placa`, tipo, marca, modelo, color, `activo` | Se relaciona con personas mediante `persona_vehiculo`; puede ser referido por `evento_acceso`. |
| `persona_vehiculo` | persona, vehículo, tipo de relación, `autorizado`, fechas de alta/baja | Historial de relaciones y autorización; admite vigencias sucesivas. |
| `usuario` | `id_usuario`, `username`, `contrasena_hash`, nombre, rol, `activo` | Opera accesos, atiende alertas y puede originar acciones. El hash debe ser Argon2id. |
| `camara` | código, nombre, `uri_stream`, resolución, `activa` | Tiene `area_vision` y puede tener `sensor`. |
| `area_vision` | cámara, código, nombre, movimiento, coordenadas normalizadas | Define una zona de entrada o salida de una cámara; recibe `deteccion`. |
| `deteccion` | área, fecha, `placa_detectada`, confianzas, tipo predicho, evidencia | Evidencia visual; puede referirse desde accesos, alertas, eventos de sensor y acciones. |
| `evento_acceso` | detección, vehículo, operador, fecha, `placa_efectiva`, movimiento, tipo, resultado, motivo | Registra una decisión de acceso y sus referencias opcionales. |
| `alerta` | acceso o detección, usuario de atención, prioridad, estado, descripción | Toda alerta debe referir al menos un acceso o una detección. |
| `sensor` | código, nombre, tipo, cámara opcional, ubicación, `activo` | Inventario físico; recibe `evento_sensor` y puede asociarse a iluminación. |
| `evento_sensor` | sensor, acceso/detección opcionales, fecha, tipo, valor, unidad | Historial de lecturas, pasos, cambios de iluminación y fallos. |
| `accion_iluminacion` | sensor, detección, usuario, origen, niveles, estado, motivo | Bitácora de órdenes; no controla hardware por sí misma. |

Las extensiones `alumno` y `administrativo` utilizan la misma clave primaria
`id_persona` como clave foránea. Las eliminaciones relacionadas usan
`ON DELETE RESTRICT`; el modelo no elimina silenciosamente evidencia histórica.

## Reglas de integridad

- Las claves primarias son UUID con `gen_random_uuid()`.
- Los textos relevantes rechazan valores vacíos o con espacios externos.
- `vehiculo.placa`, `deteccion.placa_detectada` y
  `evento_acceso.placa_efectiva` se normalizan conceptualmente en mayúsculas,
  sin espacios ni guiones; las restricciones validan ese formato.
- `vehiculo.placa` es única y representa la placa registrada del vehículo.
- `deteccion.placa_detectada` es nullable y conserva la lectura original de
  OCR/visión, si existió.
- Las confianzas de detección están entre 0 y 1.
- Las coordenadas de `area_vision` están dentro de `[0,1]` y forman un
  rectángulo válido.
- Los estados, tipos, movimientos, roles y motivos se limitan mediante
  `CHECK`.
- Una intervención manual en `evento_acceso` requiere `id_usuario_operador`.
- Una alerta debe tener referencia a un acceso o a una detección; una alerta
  atendida requiere usuario y fecha de atención.
- Los índices parciales cubren búsquedas de placas, referencias opcionales,
  estados, fechas y relaciones vigentes.

## Semántica de placas

Estas tres columnas no son equivalentes:

1. **`vehiculo.placa`**: valor registral del vehículo en el catálogo.
2. **`deteccion.placa_detectada`**: lectura original producida por la cámara y
   el OCR. Puede ser `NULL`, incorrecta o de baja confianza.
3. **`evento_acceso.placa_efectiva`**: placa normalizada utilizada para la
   decisión del evento. Puede derivarse de la detección o ser corregida por
   un operador.

El esquema no exige igualdad entre ellas. Una detección incorrecta no debe
impedir registrar evidencia ni una decisión. Asociar `evento_acceso.id_vehiculo`
con un vehículo tampoco prueba que la lectura visual haya sido correcta.
Cuando una placa se corrige, la lectura original permanece en
`deteccion.placa_detectada`; la V1 no implementa un historial específico de
quién, cuándo o por qué cambió `placa_efectiva`.

Una matrícula ausente o ilegible se representa con `NULL` en la detección y,
si corresponde, en el acceso. La autorización se expresa separadamente
mediante el resultado, motivo, vehículo y relaciones de
`persona_vehiculo`; no se deduce únicamente de una coincidencia textual.

## Migraciones y límites de V1

- `V000` habilita `pgcrypto`, valida UTF-8 y configura la sesión en UTC/public.
- `V001` crea el modelo completo.
- `V002` es un no-op: no hay triggers ni funciones de negocio.
- `V003` carga siete carreras iniciales; no crea un administrador.

La V1 no implementa el motor de visión, ingestión de vídeo, OCR, autorización
de aplicación, auditoría de correcciones de placas ni control directo de
hardware. Esas capacidades deben integrarse respetando las semánticas
anteriores y mediante migraciones nuevas si requieren persistencia adicional.

Para la verificación disponible, consultar
[`tests/V001__integrity_checks.sql`](../tests/V001__integrity_checks.sql).
