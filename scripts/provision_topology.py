#!/usr/bin/env python3
"""
Software/BD/scripts/provision_topology.py
=========================================
Herramienta CLI administrativa e idempotente para aprovisionar y validar la
topología operativa V1 de vigilancia en PostgreSQL para VIGÍA Vision Systems.

Puntos de vigilancia canónicos (DOC-01 §3.1, §7.1-7.3 y DOC-03 §4, §8 CP-TOP-01):
1. Carril de Entrada:
   - Cámara: codigo='CAM-ENTRADA', nombre='Cámara Carril Entrada', uri_stream='push://cam-entrada'
   - Área:   codigo='ROI-ENT',     nombre='Zona Lectura Entrada',  tipo_movimiento='ENTRADA'
2. Carril de Salida:
   - Cámara: codigo='CAM-SALIDA',  nombre='Cámara Carril Salida',  uri_stream='push://cam-salida'
   - Área:   codigo='ROI-SAL',     nombre='Zona Lectura Salida',   tipo_movimiento='SALIDA'

Coordenadas ROI de calibración inicial (DOC-03 §8 CP-TOP-01):
- (x_min=0.100, y_min=0.200, x_max=0.900, y_max=0.800) -> superficie normalizada 0.480 (>= 0.01).
- NOTA OPERATIVA: Estas coordenadas corresponden a la línea base nominal de DOC-03 y DEBEN
  validarse y ajustarse con imágenes reales tras fijar el ángulo físico del dispositivo en caseta.

Garantías:
- No modifica las migraciones cerradas V001, V002 ni V003.
- Idempotente: Si las cámaras y áreas ya existen, no duplica registros ni altera datos
  salvo que se indique explícitamente --update-existing.
- Verifica al finalizar el cumplimiento estricto de las reglas R1–R8 mediante TopologyValidator
  y PsycopgTopologyConfigRepository contra PostgreSQL.
"""

from __future__ import annotations

import argparse
import sys
from decimal import Decimal
from pathlib import Path
from typing import Tuple

# Resolver ruta a VIGIA_Vision_Systems para importar módulos de VIGIA_Core y VIGIA_Vision
_script_dir = Path(__file__).resolve().parent
_possible_roots = [
    _script_dir.parent.parent / "VIGIA_Vision_Systems",
    _script_dir.parent / "VIGIA_Vision_Systems",
    Path("VIGIA_Vision_Systems").resolve(),
    Path("../VIGIA_Vision_Systems").resolve(),
]
for root in _possible_roots:
    if root.exists() and (root / "VIGIA_Core").exists():
        if str(root) not in sys.path:
            sys.path.insert(0, str(root))
        break

try:
    import psycopg2
    from VIGIA_Core.repository.detection_repository import DatabaseConnectionError
    from VIGIA_Core.repository.user_repository import resolve_database_dsn
    from VIGIA_Vision.config.psycopg_topology_repository import PsycopgTopologyConfigRepository
    from VIGIA_Vision.config.topology_validator import TopologyValidator
except ImportError as exc:
    sys.stderr.write(
        f"Error crítico al importar componentes de VIGÍA: {exc}\n"
        "Verifica que el entorno virtual esté activo y VIGIA_Vision_Systems en PYTHONPATH.\n"
    )
    sys.exit(1)


# Coordenadas nominales documentadas en DOC-03 §8 (CP-TOP-01)
DEFAULT_ROI_ENTRADA = "0.100,0.200,0.900,0.800"
DEFAULT_ROI_SALIDA = "0.100,0.200,0.900,0.800"


def parse_roi_Box(raw_roi: str, label: str) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
    """Valida que la cadena 'x_min,y_min,x_max,y_max' cumpla las restricciones DDL V001 y R7/R8."""
    parts = [p.strip() for p in raw_roi.split(",") if p.strip()]
    if len(parts) != 4:
        raise ValueError(
            f"Formato inválido en {label}='{raw_roi}'. Se esperan 4 valores separados por coma: x_min,y_min,x_max,y_max."
        )
    try:
        x_min, y_min, x_max, y_max = (Decimal(p) for p in parts)
    except Exception as err:
        raise ValueError(f"Coordenadas no numéricas en {label}='{raw_roi}': {err}") from err

    if not (Decimal("0.000") <= x_min < x_max <= Decimal("1.000")):
        raise ValueError(
            f"Coordenadas X fuera de rango en {label}: se requiere 0.0 <= x_min ({x_min}) < x_max ({x_max}) <= 1.0."
        )
    if not (Decimal("0.000") <= y_min < y_max <= Decimal("1.000")):
        raise ValueError(
            f"Coordenadas Y fuera de rango en {label}: se requiere 0.0 <= y_min ({y_min}) < y_max ({y_max}) <= 1.0."
        )

    area = (x_max - x_min) * (y_max - y_min)
    if area < Decimal(str(TopologyValidator.UMBRAL_AREA_ROI_MINIMA)):
        raise ValueError(
            f"Superficie ROI degenerada en {label}: área={area:.4f} es menor al mínimo permitido "
            f"({TopologyValidator.UMBRAL_AREA_ROI_MINIMA})."
        )
    return (
        x_min.quantize(Decimal("0.001")),
        y_min.quantize(Decimal("0.001")),
        x_max.quantize(Decimal("0.001")),
        y_max.quantize(Decimal("0.001")),
    )


def validate_stream_uri(uri: str, camera_code: str) -> str:
    cleaned = (uri or "").strip()
    if not cleaned:
        raise ValueError(f"El uri_stream para '{camera_code}' no puede ser vacío.")
    if cleaned.isdigit():
        return f"usb://{cleaned}"
    allowed_prefixes = ("push://", "mobile://", "usb://", "rtsp://", "rtsps://", "http://", "https://")
    if not cleaned.lower().startswith(allowed_prefixes):
        raise ValueError(
            f"El uri_stream '{cleaned}' para '{camera_code}' debe iniciar con uno de los esquemas "
            f"soportados por CameraSourceRegistry: {allowed_prefixes} o un índice numérico (ej. '0')."
        )
    return cleaned


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aprovisionamiento administrativo idempotente de la topología operativa V1 (CAM-ENTRADA y CAM-SALIDA)."
    )
    parser.add_argument(
        "--uri-entrada",
        type=str,
        default="push://cam-entrada",
        help="URI de captura para CAM-ENTRADA (por omisión: push://cam-entrada para MobilePushFrameBuffer).",
    )
    parser.add_argument(
        "--uri-salida",
        type=str,
        default="push://cam-salida",
        help="URI de captura para CAM-SALIDA (por omisión: push://cam-salida para MobilePushFrameBuffer).",
    )
    parser.add_argument(
        "--roi-entrada",
        type=str,
        default=DEFAULT_ROI_ENTRADA,
        help=f"Coordenadas normalizadas x_min,y_min,x_max,y_max para ROI-ENT (por omisión DOC-03: {DEFAULT_ROI_ENTRADA}).",
    )
    parser.add_argument(
        "--roi-salida",
        type=str,
        default=DEFAULT_ROI_SALIDA,
        help=f"Coordenadas normalizadas x_min,y_min,x_max,y_max para ROI-SAL (por omisión DOC-03: {DEFAULT_ROI_SALIDA}).",
    )
    parser.add_argument(
        "--update-existing",
        action="store_true",
        help="Actualiza uri_stream, coordenadas ROI y estado activo si los registros canónicos ya existen.",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Solo verifica la topología actual en PostgreSQL contra las reglas R1–R8 sin insertar ni modificar datos.",
    )
    return parser.parse_args()


def _upsert_camera_and_area(
    cur,
    *,
    cam_codigo: str,
    cam_nombre: str,
    uri_stream: str,
    area_codigo: str,
    area_nombre: str,
    tipo_movimiento: str,
    roi_coords: Tuple[Decimal, Decimal, Decimal, Decimal],
    update_existing: bool,
) -> Tuple[str, str, str]:
    """
    Inserta o verifica de forma idempotente una cámara canónica y su área de visión asociada.
    Retorna (id_camara, id_area_vision, accion_realizada).
    """
    x_min, y_min, x_max, y_max = roi_coords
    cur.execute(
        "SELECT id_camara, uri_stream, activa FROM camara WHERE codigo = %s;",
        (cam_codigo,),
    )
    cam_row = cur.fetchone()
    action_parts = []

    if cam_row is None:
        cur.execute(
            """
            INSERT INTO camara (codigo, nombre, uri_stream, activa)
            VALUES (%s, %s, %s, TRUE)
            RETURNING id_camara;
            """,
            (cam_codigo, cam_nombre, uri_stream),
        )
        id_camara = str(cur.fetchone()[0])
        action_parts.append("cámara creada")
    else:
        id_camara = str(cam_row[0])
        if update_existing:
            cur.execute(
                """
                UPDATE camara
                SET nombre = %s, uri_stream = %s, activa = TRUE
                WHERE id_camara = %s;
                """,
                (cam_nombre, uri_stream, id_camara),
            )
            action_parts.append("cámara actualizada")
        else:
            action_parts.append("cámara existente preservada")

    cur.execute(
        """
        SELECT id_area_vision
        FROM area_vision
        WHERE id_camara = %s AND codigo = %s;
        """,
        (id_camara, area_codigo),
    )
    area_row = cur.fetchone()

    if area_row is None:
        cur.execute(
            """
            INSERT INTO area_vision (
                id_camara, codigo, nombre, tipo_movimiento,
                x_min, y_min, x_max, y_max, activa
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, TRUE)
            RETURNING id_area_vision;
            """,
            (
                id_camara,
                area_codigo,
                area_nombre,
                tipo_movimiento,
                x_min,
                y_min,
                x_max,
                y_max,
            ),
        )
        id_area_vision = str(cur.fetchone()[0])
        action_parts.append("área creada")
    else:
        id_area_vision = str(area_row[0])
        if update_existing:
            cur.execute(
                """
                UPDATE area_vision
                SET nombre = %s,
                    tipo_movimiento = %s,
                    x_min = %s,
                    y_min = %s,
                    x_max = %s,
                    y_max = %s,
                    activa = TRUE
                WHERE id_area_vision = %s;
                """,
                (
                    area_nombre,
                    tipo_movimiento,
                    x_min,
                    y_min,
                    x_max,
                    y_max,
                    id_area_vision,
                ),
            )
            action_parts.append("área actualizada")
        else:
            action_parts.append("área existente preservada")

    return id_camara, id_area_vision, ", ".join(action_parts)


def main() -> int:
    args = parse_arguments()

    try:
        uri_ent = validate_stream_uri(args.uri_entrada, TopologyValidator.CODIGO_CAM_ENTRADA)
        uri_sal = validate_stream_uri(args.uri_salida, TopologyValidator.CODIGO_CAM_SALIDA)
        roi_ent = parse_roi_Box(args.roi_entrada, "roi-entrada")
        roi_sal = parse_roi_Box(args.roi_salida, "roi-salida")
    except ValueError as val_err:
        sys.stderr.write(f"Error de validación de parámetros: {val_err}\n")
        return 1

    try:
        dsn = resolve_database_dsn()
    except Exception as exc:
        sys.stderr.write(f"Fallo al resolver la configuración de conexión a PostgreSQL: {exc}\n")
        return 1

    if not args.verify_only:
        conn = None
        try:
            conn = psycopg2.connect(dsn)
            with conn:
                with conn.cursor() as cur:
                    id_cam_ent, id_area_ent, act_ent = _upsert_camera_and_area(
                        cur,
                        cam_codigo=TopologyValidator.CODIGO_CAM_ENTRADA,
                        cam_nombre="Cámara Carril Entrada",
                        uri_stream=uri_ent,
                        area_codigo="ROI-ENT",
                        area_nombre="Zona Lectura Entrada",
                        tipo_movimiento=TopologyValidator.MOVIMIENTO_ENTRADA,
                        roi_coords=roi_ent,
                        update_existing=args.update_existing,
                    )
                    id_cam_sal, id_area_sal, act_sal = _upsert_camera_and_area(
                        cur,
                        cam_codigo=TopologyValidator.CODIGO_CAM_SALIDA,
                        cam_nombre="Cámara Carril Salida",
                        uri_stream=uri_sal,
                        area_codigo="ROI-SAL",
                        area_nombre="Zona Lectura Salida",
                        tipo_movimiento=TopologyValidator.MOVIMIENTO_SALIDA,
                        roi_coords=roi_sal,
                        update_existing=args.update_existing,
                    )

            sys.stdout.write(
                "=== Aprovisionamiento Topológico V1 ===\n"
                f"  - CAM-ENTRADA ({id_cam_ent}) / ROI-ENT ({id_area_ent}): {act_ent}\n"
                f"  - CAM-SALIDA  ({id_cam_sal}) / ROI-SAL ({id_area_sal}): {act_sal}\n"
            )
        except Exception as db_exc:
            sys.stderr.write(f"Error relacional en PostgreSQL durante el aprovisionamiento: {db_exc}\n")
            return 1
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass

    # Verificación formal mediante PsycopgTopologyConfigRepository + TopologyValidator (Reglas R1–R8)
    try:
        topo_repo = PsycopgTopologyConfigRepository(dsn=dsn)
        validator = TopologyValidator(repository=topo_repo)
        res = validator.validate()
    except DatabaseConnectionError as conn_err:
        sys.stderr.write(f"Error de conexión al validar la topología en PostgreSQL: {conn_err}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Error inesperado durante la validación topológica: {exc}\n")
        return 1

    if not res.is_valid or res.topology is None:
        sys.stderr.write(
            f"FALLO DE VALIDACIÓN TOPOLÓGICA (Reglas R1–R8): [{res.error_code}] {res.error_detail}\n"
        )
        return 1

    topo = res.topology
    sys.stdout.write(
        "=== Validación Topológica R1–R8: APROBADA ===\n"
        f"  [ENTRADA] Cámara: {topo.cam_entrada.codigo} (id={topo.cam_entrada.id_camara}, uri='{topo.cam_entrada.uri_stream}', activa={topo.cam_entrada.activa})\n"
        f"            Área:   {topo.area_entrada.codigo} (id={topo.area_entrada.id_area_vision}, mov={topo.area_entrada.tipo_movimiento}, "
        f"ROI=[{topo.area_entrada.x_min:.3f}, {topo.area_entrada.y_min:.3f}, {topo.area_entrada.x_max:.3f}, {topo.area_entrada.y_max:.3f}])\n"
        f"  [SALIDA]  Cámara: {topo.cam_salida.codigo} (id={topo.cam_salida.id_camara}, uri='{topo.cam_salida.uri_stream}', activa={topo.cam_salida.activa})\n"
        f"            Área:   {topo.area_salida.codigo} (id={topo.area_salida.id_area_vision}, mov={topo.area_salida.tipo_movimiento}, "
        f"ROI=[{topo.area_salida.x_min:.3f}, {topo.area_salida.y_min:.3f}, {topo.area_salida.x_max:.3f}, {topo.area_salida.y_max:.3f}])\n"
        "AVISO DE CALIBRACIÓN: Las coordenadas ROI iniciales corresponden a la línea base nominal (DOC-03 CP-TOP-01).\n"
        "Deben validarse con imágenes reales del carril físico y recalibrarse con --update-existing si el encuadre cambia.\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
