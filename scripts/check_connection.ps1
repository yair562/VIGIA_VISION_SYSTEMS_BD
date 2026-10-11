param(
    [string]$Host = "localhost",
    [int]$Port = 5433,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\.env")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "No existe el archivo de entorno: $EnvFile. Copia .env.example como .env."
}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "No se encontró psql en PATH. Instala PostgreSQL o agrega su carpeta bin al PATH."
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

$env:PGPASSWORD = $values["POSTGRES_PASSWORD"]
try {
    & psql --host=$Host --port=$Port --username=$values["POSTGRES_USER"] --dbname=$values["POSTGRES_DB"] --command="SELECT current_database(), current_user, version();" --set=ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) {
        throw "No fue posible conectarse a PostgreSQL (código $LASTEXITCODE)."
    }
    Write-Host "Conexión verificada correctamente."
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}