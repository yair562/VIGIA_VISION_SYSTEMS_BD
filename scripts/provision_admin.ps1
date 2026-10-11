<#
.SYNOPSIS
    Aprovisiona el usuario administrador de VIGIA.
.DESCRIPTION
    Esta operación permanece bloqueada hasta disponer de la implementación
    Argon2id compatible con el backend. No genera bcrypt ni hashes ficticios.
#>
[CmdletBinding()]
param(
    [string]$Username = "admin",
    [string]$FullName = "Administrador VIGIA",
    [System.Security.SecureString]$SecurePassword = $null
)

$ErrorActionPreference = "Stop"
throw "Aprovisionamiento detenido: el backend accesible no implementa autenticacion ni provee una biblioteca Argon2id compatible. No se generara bcrypt ni se almacenara una credencial ficticia."
