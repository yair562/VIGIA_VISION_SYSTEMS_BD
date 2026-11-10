#!/usr/bin/env python3
"""
Software/BD/scripts/provision_admin.py
======================================
Herramienta CLI de aprovisionamiento seguro del primer usuario administrador
para VIGÍA Vision Systems.

Requisitos de Seguridad y Arquitectura:
- Derivación estricta de hash con Argon2id mediante VIGIA_Core.security.password_hasher.
- Persistencia real en PostgreSQL mediante PsycopgUserRepository.
- Lectura segura de contraseña mediante getpass interactivo o variable de entorno
  VIGIA_ADMIN_PASSWORD. Prohibido recibir contraseñas por argumentos de CLI.
- Idempotencia: Si el usuario ya existe en PostgreSQL, aborta sin modificar ni sobrescribir.
- Rol admitido en V001: 'ADMINISTRADOR', 'OPERADOR' o 'AUDITOR' (por omisión 'ADMINISTRADOR').
- Cero fugas de credenciales en stdout, stderr o registros persistentes.
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

# Resolver ruta a VIGIA_Vision_Systems para importar módulos de VIGIA_Core
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
    from VIGIA_Core.domain.user import UserDTO
    from VIGIA_Core.repository.detection_repository import (
        DatabaseConnectionError,
        DatabasePersistenceError,
    )
    from VIGIA_Core.repository.user_repository import (
        PsycopgUserRepository,
        resolve_database_dsn,
    )
    from VIGIA_Core.security.password_hasher import hash_password
except ImportError as exc:
    sys.stderr.write(
        f"Error crítico al importar componentes de VIGIA_Core: {exc}\n"
        "Verifica que el entorno virtual esté activo y VIGIA_Vision_Systems en PYTHONPATH.\n"
    )
    sys.exit(1)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aprovisionamiento seguro del primer administrador de VIGÍA Vision Systems."
    )
    parser.add_argument(
        "--username",
        type=str,
        default="admin",
        help="Nombre de usuario a registrar (por omisión: admin).",
    )
    parser.add_argument(
        "--fullname",
        type=str,
        default="Administrador VIGÍA",
        help="Nombre completo del usuario (por omisión: Administrador VIGÍA).",
    )
    parser.add_argument(
        "--role",
        type=str,
        default="ADMINISTRADOR",
        choices=["ADMINISTRADOR", "OPERADOR", "AUDITOR"],
        help="Rol institucional según V001 (por omisión: ADMINISTRADOR).",
    )
    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Modo no interactivo; exige que la variable VIGIA_ADMIN_PASSWORD esté definida.",
    )
    return parser.parse_args()


def get_secure_password(non_interactive: bool = False) -> str:
    env_pwd = os.environ.get("VIGIA_ADMIN_PASSWORD", "").strip()
    if env_pwd:
        if len(env_pwd) < 8:
            sys.stderr.write("Error: La contraseña provista en VIGIA_ADMIN_PASSWORD debe tener al menos 8 caracteres.\n")
            sys.exit(1)
        return env_pwd

    if non_interactive:
        sys.stderr.write(
            "Error: En modo no interactivo (--non-interactive), se debe definir la variable de entorno VIGIA_ADMIN_PASSWORD.\n"
        )
        sys.exit(1)

    while True:
        try:
            pwd = getpass.getpass("Ingresa la contraseña para el nuevo usuario (mínimo 8 caracteres): ")
        except (KeyboardInterrupt, EOFError):
            sys.stderr.write("\nOperación cancelada por el usuario.\n")
            sys.exit(130)

        if len(pwd.strip()) < 8:
            sys.stderr.write("La contraseña debe tener al menos 8 caracteres. Intenta de nuevo.\n")
            continue

        try:
            pwd_confirm = getpass.getpass("Confirma la contraseña: ")
        except (KeyboardInterrupt, EOFError):
            sys.stderr.write("\nOperación cancelada por el usuario.\n")
            sys.exit(130)

        if pwd != pwd_confirm:
            sys.stderr.write("Las contraseñas no coinciden. Intenta de nuevo.\n")
            continue

        return pwd


def provision_user() -> int:
    args = parse_arguments()
    raw_password = get_secure_password(non_interactive=args.non_interactive)

    # 1. Derivación del hash Argon2id (nunca se almacena ni imprime en texto plano)
    try:
        pw_hash = hash_password(raw_password)
    except Exception as exc:
        sys.stderr.write(f"Error criptográfico al derivar contraseña con Argon2id: {exc}\n")
        return 1
    finally:
        # Purgar referencia local a la contraseña en texto plano
        del raw_password

    # 2. Conexión con PostgreSQL
    try:
        dsn = resolve_database_dsn()
        repo = PsycopgUserRepository(dsn=dsn)
    except DatabaseConnectionError as conn_err:
        sys.stderr.write(f"Error al conectar con PostgreSQL: {conn_err}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Fallo de configuración de base de datos: {exc}\n")
        return 1

    # 3. Verificación de existencia previa (idempotencia)
    try:
        existing = repo.get_by_username(args.username)
        if existing is not None:
            sys.stdout.write(
                f"Aviso: El usuario '{args.username}' ya se encuentra registrado en PostgreSQL.\n"
                "Operación abortada sin realizar modificaciones (idempotente).\n"
            )
            return 0
    except Exception as exc:
        sys.stderr.write(f"Error al consultar usuarios existentes: {exc}\n")
        return 1

    # 4. Creación y persistencia transaccional del usuario
    try:
        user_dto = UserDTO(
            username=args.username,
            contrasena_hash=pw_hash,
            nombre_completo=args.fullname,
            rol=args.role,
            activo=True,
        )
        user_id = repo.create_user(user_dto)
        sys.stdout.write(
            f"Éxito: Usuario '{args.username}' ({args.role}) aprovisionado exitosamente en PostgreSQL.\n"
            f"ID de Usuario: {user_id}\n"
        )
        return 0
    except DatabasePersistenceError as persist_err:
        sys.stderr.write(f"Error de persistencia relacional al crear usuario: {persist_err}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Error inesperado al insertar usuario en la base de datos: {exc}\n")
        return 1


if __name__ == "__main__":
    sys.exit(provision_user())
