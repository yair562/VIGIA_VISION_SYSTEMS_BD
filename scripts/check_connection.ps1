param(
    [string]$DbHost = "localhost",
    [int]$Port = 0,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\..\.env")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "No existe el archivo de entorno: $EnvFile. Copia Software/.env.example como Software/.env."
}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "No se encontr psql en PATH. Instala PostgreSQL o agrega su carpeta bin al PATH."
}

$values = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
        $values[$Matches[1]] = $Matches[2].Trim('"', "'")
    }
}
foreach ($required in @("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD")) {
    if (-not $values.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($values[$required])) {
        throw "Falta la variable $required en $EnvFile."
    }
}

if ($Port -eq 0) {
    if ($values.ContainsKey("POSTGRES_PORT") -and -not [string]::IsNullOrWhiteSpace($values["POSTGRES_PORT"])) {
        $Port = [int]$values["POSTGRES_PORT"]
    } else {
        $Port = 5434
    }
}

$targetUser = $values["POSTGRES_USER"]
$targetDb = $values["POSTGRES_DB"]
$env:PGPASSWORD = $values["POSTGRES_PASSWORD"]
try {
    & psql --host=$DbHost --port=$Port --username=$targetUser --dbname=$targetDb --command="SELECT current_database(), current_user, version();" --set=ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) {
        throw "No fue posible conectarse a PostgreSQL (cdigo $LASTEXITCODE)."
    }
    Write-Host "Conexin verificada correctamente."
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
