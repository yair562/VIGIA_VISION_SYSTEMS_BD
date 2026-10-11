# Arquitectura inicial del motor de visión

## 1. Propósito y límites

El motor de visión propuesto transforma imágenes o fotogramas de cámaras en
observaciones estructuradas para VIGIA. Su responsabilidad termina en producir
detecciones con evidencia y confianza. No decide por sí mismo si un vehículo
está autorizado, no concede acceso, no modifica el catálogo de vehículos y no
controla barreras o luminarias.

Esta es una propuesta arquitectónica; no existe todavía un motor implementado
en este repositorio.

## 2. Flujo conceptual

1. Un origen de vídeo entrega un fotograma junto con una referencia temporal.
2. El motor identifica la cámara y carga sus `area_vision` activas.
3. Detecta vehículos dentro de las áreas relevantes.
4. Intenta reconocer la matrícula mediante OCR.
5. Produce una observación con resultado, confianzas y referencia de evidencia.
6. Una capa posterior decide si crea `evento_acceso`; esa decisión no pertenece
   al detector.

La configuración persistida existente está en `camara` y `area_vision`.
`deteccion` es la entidad V1 destinada a guardar el resultado visual.

## 3. Entrada

La entrada mínima propuesta contiene:

- identificador o código de cámara;
- fotograma o referencia temporal al fotograma;
- fecha y hora con zona horaria;
- resolución y, si aplica, dirección de movimiento;
- configuración vigente de las áreas de visión.

El mecanismo de transporte, formato de vídeo, hardware y política de
almacenamiento de imágenes siguen pendientes. `camara.uri_stream` existe en la
BD, pero no prescribe por sí solo cómo se implementará la captura.

## 4. Detección y OCR

El procesamiento debe separar dos resultados conceptuales:

- **vehículo detectado**: localización/clase y confianza del vehículo;
- **matrícula detectada**: texto OCR, confianza y evidencia asociada.

Si no se encuentra matrícula, el resultado debe conservar la detección del
vehículo cuando exista y dejar `placa_detectada` en `NULL`. Una lectura
ilegible o de baja confianza no debe convertirse artificialmente en una placa
válida. La decisión del umbral y la posibilidad de reintento quedan
pendientes de validación con datos reales.

La estructura persistente V1 disponible para una detección es:

```text
deteccion
  id_area_vision
  fecha_hora
  placa_detectada
  confianza_placa
  confianza_vehiculo
  tipo_vehiculo_pred
  ruta_evidencia_foto
```

No se deben inventar campos para cajas delimitadoras, modelo, versión o
seguimiento sin una migración aprobada.

## 5. Relación con acceso

`deteccion.placa_detectada` conserva la observación original. Una capa de
negocio puede normalizarla y usarla como `evento_acceso.placa_efectiva`, o
registrar una corrección manual. `vehiculo.placa` es el valor registral y
puede diferir legítimamente de ambas lecturas.

La asociación `evento_acceso.id_vehiculo` es una referencia para la decisión,
no una prueba de que el OCR acertó. La autorización debe consultar las reglas
de negocio y las relaciones de `persona_vehiculo`; no debe ser una función
implícita del motor de visión.

## 6. Salidas y estados conceptuales

Una salida del motor debería incluir, como mínimo:

- cámara y área de visión;
- instante de captura;
- vehículo detectado y su confianza, si aplica;
- texto OCR y confianza, si aplica;
- referencia a la evidencia;
- estado técnico del procesamiento y errores no sensibles.

Estos campos son un contrato conceptual, no una afirmación de que todos
existan hoy en PostgreSQL. La persistencia compatible con V1 debe proyectarse
únicamente a las columnas reales de `deteccion`.

## 7. Integración futura

La integración recomendada separa tres pasos:

1. **Visión:** produce `deteccion`.
2. **Negocio:** interpreta la detección, consulta vehículos y autorizaciones y
   decide `evento_acceso`.
3. **Operación:** genera alertas o acciones, si corresponde.

El canal entre componentes, autenticación, reintentos, idempotencia y
observabilidad aún requieren diseño. PostgreSQL puede ser el destino de
persistencia, pero el motor no debe escribir directamente decisiones de
autorización sin pasar por una interfaz de negocio definida.

## 8. Componentes confirmados, pendientes y riesgos

### Confirmado

- PostgreSQL 16 y el esquema V1.
- `camara`, `area_vision`, `deteccion` y `evento_acceso`.
- Restricciones de formato y confianza.
- Separación entre evidencia y decisión.

### Pendiente

- Librería o modelo de detección/OCR.
- Protocolo de comunicación y formato de mensajes.
- Hardware, aceleración y estrategia de captura.
- Umbrales de confianza y política de revisión manual.
- Retención y protección de imágenes.
- Versionado de modelos y métricas de calidad.

### Riesgos

- Iluminación, reflejos, oclusiones y ángulos pueden degradar OCR.
- Normalizar demasiado pronto puede perder evidencia.
- Reintentos pueden duplicar detecciones si no existe una clave de
  idempotencia definida.
- La placa OCR no demuestra autorización ni identidad del conductor.
- Almacenar imágenes puede introducir requisitos legales y de capacidad.

## 9. Plan incremental

1. Definir un contrato de entrada/salida y un conjunto de datos de prueba,
   sin conectarlo aún al control de acceso.
2. Implementar captura controlada y registrar detecciones de prueba.
3. Medir detección de vehículos y OCR por separado, incluyendo casos sin
   matrícula y lecturas incorrectas.
4. Persistir únicamente los campos compatibles con `deteccion`.
5. Añadir una revisión manual que conserve la lectura original.
6. Integrar la decisión de acceso mediante una capa de negocio separada.
7. Evaluar posteriormente nuevas migraciones solo si las métricas y requisitos
   demuestran que faltan datos persistentes.
