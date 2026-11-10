<#
.SYNOPSIS
    Aprovisiona el usuario administrador de VIGIA.
.DESCRIPTION
    Invoca la herramienta CLI segura provision_admin.py, derivando contraseñas con
    Argon2id y persistiendo de forma transaccional e idempotente en PostgreSQL 16.
#>
[CmdletBinding()]
param(
    [string]$Username = "admin",
    [string]$FullName = "Administrador VIGIA",
    [System.Security.SecureString]$SecurePassword = $null,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "provision_admin.py"
$pythonExe = Join-Path $scriptDir "..\..\VIGIA_Vision_Systems\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $pythonExe)) {
    $pythonExe = "python"
}

$hadSecurePassword = $false
if ($null -ne $SecurePassword) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        $env:VIGIA_ADMIN_PASSWORD = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $NonInteractive = $true
        $hadSecurePassword = $true
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

try {
    $cmdArgs = @($pythonScript, "--username", $Username, "--fullname", $FullName)
    if ($NonInteractive) {
        $cmdArgs += "--non-interactive"
    }
    & $pythonExe @cmdArgs
    if ($LASTEXITCODE -ne 0) {
        throw "El aprovisionamiento de usuario falló con código de salida $LASTEXITCODE."
    }
}
finally {
    if ($hadSecurePassword) {
        Remove-Item Env:VIGIA_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    }
}
