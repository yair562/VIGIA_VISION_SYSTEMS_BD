
<#
.SYNOPSIS
    Ejecutor de migraciones versionadas para VIGIA Vision Systems.
.DESCRIPTION
    Aplica migraciones V<numero>__<descripcion>.sql en orden numerico.
    Registra SHA-256 en public.schema_version.
    Utiliza transacciones y bloqueos para evitar ejecuciones concurrentes.
    No elimina bases, tablas ni volumenes.
#>

[CmdletBinding()]
param(
    [string]$DbHost = "localhost",
    [int]$Port = 5433,
    [string]$Database,
    [string]$User,
    [string]$EnvFile,
    [string]$MigrationsDir,
    [switch]$AllowNonVigiaDatabase
)

$ErrorActionPreference = "Stop"
$exitCode = 0
$mutex = $null
$mutexAcquired = $false
$oldPassword = $env:PGPASSWORD
$oldEncoding = $env:PGCLIENTENCODING

try {
    # 1. Resolver rutas DESPUES de param().
    $scriptRoot = $PSScriptRoot

    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        throw "No se pudo determinar la ruta del script."
    }

    if ([string]::IsNullOrWhiteSpace($EnvFile)) {
        $EnvFile = Join-Path $scriptRoot "..\.env"
    }

    if ([string]::IsNullOrWhiteSpace($MigrationsDir)) {
        $MigrationsDir = Join-Path $scriptRoot "..\migrations"
    }

    $EnvFile = [System.IO.Path]::GetFullPath($EnvFile)
    $MigrationsDir = [System.IO.Path]::GetFullPath($MigrationsDir)

    # 2. Comprobar dependencias y archivos.
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        throw "No se encontro psql en PATH. Instala PostgreSQL o configura su carpeta bin."
    }

    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
        throw "No existe el archivo .env esperado: $EnvFile"
    }

    if (-not (Test-Path -LiteralPath $MigrationsDir -PathType Container)) {
        throw "No existe el directorio de migraciones: $MigrationsDir"
    }

    # 3. Leer .env sin mostrar credenciales.
    $envValues = @{}

    foreach ($rawLine in Get-Content -LiteralPath $EnvFile) {
        $line = $rawLine.Trim()

        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()

            if (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            ) {
                $value = $value.Substring(1, $value.Length - 2)
            }

            $envValues[$key] = $value
        }
    }

    $targetDb = if ($Database) {
        $Database
    } else {
        $envValues["POSTGRES_DB"]
    }

    $targetUser = if ($User) {
        $User
    } else {
        $envValues["POSTGRES_USER"]
    }

    $targetPass = $envValues["POSTGRES_PASSWORD"]

    if (
        [string]::IsNullOrWhiteSpace($targetDb) -or
        [string]::IsNullOrWhiteSpace($targetUser) -or
        [string]::IsNullOrWhiteSpace($targetPass)
    ) {
        throw "Faltan POSTGRES_DB, POSTGRES_USER o POSTGRES_PASSWORD en .env."
    }

    # Proteccion contra un destino equivocado.
    if ((-not $AllowNonVigiaDatabase -and $targetDb -ne "vigia_db") -or $Port -ne 5433) {
        throw "Destino rechazado. Este despliegue requiere vigia_db en el puerto 5433. No se modifico el esquema."
    }

    $env:PGPASSWORD = $targetPass
    $env:PGCLIENTENCODING = "UTF8"

    Write-Host "============================================================"
    Write-Host " VIGIA Vision Systems - Migraciones PostgreSQL"
    Write-Host "============================================================"
    Write-Host "Destino: ${DbHost}:$Port / $targetDb / $targetUser"
    Write-Host "Migraciones: $MigrationsDir"

    # 4. Comprobar conexion antes de modificar el esquema.
    & psql -X --host=$DbHost --port=$Port --username=$targetUser `
        --dbname=$targetDb --no-password -q `
        --set=ON_ERROR_STOP=1 `
        --command="SELECT 1;" 

    if ($LASTEXITCODE -ne 0) {
        throw "No fue posible conectar al destino configurado."
    }

    # Verificar que la conexion corresponde a la base esperada.
    $identity = & psql -X --host=$DbHost --port=$Port `
        --username=$targetUser --dbname=$targetDb --no-password `
        -At --set=ON_ERROR_STOP=1 `
        --command="SELECT current_database() || '|' || current_setting('port');"

    $expectedIdentity = "$targetDb|5432"
    if ($LASTEXITCODE -ne 0 -or $identity.Trim() -ne $expectedIdentity) {
        throw "La identidad de la conexion no coincide con el destino esperado."
    }

    # 5. Bloqueo local del ejecutor.
    $mutex = New-Object System.Threading.Mutex(
        $false,
        "Global\VIGIA_Vision_Systems_Migrations"
    )

    if (-not $mutex.WaitOne(0)) {
        throw "Ya existe otra ejecucion del migrador en este equipo."
    }

    $mutexAcquired = $true

    # 6. Crear tabla de historial si aun no existe.
    $initSql = @"
\set ON_ERROR_STOP on
CREATE TABLE IF NOT EXISTS public.schema_version (
    version VARCHAR(50) PRIMARY KEY,
    archivo VARCHAR(255) NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    aplicado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tiempo_ms INTEGER NOT NULL
);
"@

    $initSql | & psql -X --host=$DbHost --port=$Port `
        --username=$targetUser --dbname=$targetDb --no-password -q `
        --set=ON_ERROR_STOP=1

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo inicializar public.schema_version."
    }

    # 7. No adoptar silenciosamente esquemas sin historial.
    $historyCount = & psql -X --host=$DbHost --port=$Port `
        --username=$targetUser --dbname=$targetDb --no-password `
        -At --set=ON_ERROR_STOP=1 `
        --command="SELECT count(*) FROM public.schema_version;"

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo leer el historial de migraciones."
    }

    $businessTables = & psql -X --host=$DbHost --port=$Port `
        --username=$targetUser --dbname=$targetDb --no-password `
        -At --set=ON_ERROR_STOP=1 `
        --command="SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name <> 'schema_version';"

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo verificar el esquema existente."
    }

    if ([int]$historyCount -eq 0 -and [int]$businessTables -gt 0) {
        throw "Hay tablas de negocio sin historial de migraciones. Se cancela para evitar duplicar el esquema. No se admite adopcion automatica."
    }

    # 8. Cargar versiones registradas.
    $appliedRows = & psql -X --host=$DbHost --port=$Port `
        --username=$targetUser --dbname=$targetDb --no-password `
        -At -F "|" --set=ON_ERROR_STOP=1 `
        --command="SELECT version, checksum, archivo, to_char(aplicado_en, 'YYYY-MM-DD HH24:MI:SS') FROM public.schema_version ORDER BY version;"

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo cargar el historial de migraciones."
    }

    $appliedMap = @{}

    foreach ($row in $appliedRows) {
        if ([string]::IsNullOrWhiteSpace($row)) {
            continue
        }

        $parts = $row.Split("|")

        if ($parts.Length -ne 4) {
            throw "Registro inesperado en public.schema_version."
        }

        $appliedMap[$parts[0]] = @{
            Checksum   = $parts[1]
            Archivo    = $parts[2]
            AplicadoEn = $parts[3]
        }
    }

    # 9. Descubrir migraciones activas y ordenarlas numericamente.
    $migrationFiles = @(
        Get-ChildItem -LiteralPath $MigrationsDir -Filter "V*__*.sql" -File |
        Sort-Object {
            if ($_.Name -match '^V(\d+)__') {
                [long]$Matches[1]
            } else {
                [long]::MaxValue
            }
        }
    )

    if ($migrationFiles.Count -eq 0) {
        throw "No se encontraron migraciones activas V<numero>__<descripcion>.sql."
    }

    $versionSeen = @{}

    foreach ($file in $migrationFiles) {
        if ($file.Name -notmatch '^(V\d+)__(.+)\.sql$') {
            throw "Nombre de migracion no valido: $($file.Name)"
        }

        $versionKey = $Matches[1]

        if ($versionSeen.ContainsKey($versionKey)) {
            throw "Version duplicada: $versionKey."
        }

        $versionSeen[$versionKey] = $file.Name
    }

    # 10. Aplicar migraciones en orden.
    $appliedCount = 0

    foreach ($file in $migrationFiles) {
        $null = $file.Name -match '^(V\d+)__(.+)\.sql$'
        $version = $Matches[1]

        $rawBytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $sha = [System.Security.Cryptography.SHA256]::Create()

        try {
            $hashBytes = $sha.ComputeHash($rawBytes)
            $checksum = -join ($hashBytes | ForEach-Object {
                $_.ToString("x2")
            })
        }
        finally {
            $sha.Dispose()
        }

        if ($appliedMap.ContainsKey($version)) {
            $previous = $appliedMap[$version]

            if ($previous.Checksum -ne $checksum) {
                throw "CONFLICTO SHA-256 en $version. No se ejecutara una migracion historica modificada."
            }

            if ($previous.Archivo -ne $file.Name) {
                throw "El nombre de archivo de $version no coincide con el historial."
            }

            Write-Host "[OMITIDA] $version ya aplicada."
            continue
        }

        $fileContent = [System.IO.File]::ReadAllText(
            $file.FullName,
            [System.Text.Encoding]::UTF8
        )

        # ALTER DATABASE requiere otro contexto de conexion.
        # No ejecutarlo dentro de la transaccion automatica.
        if ($fileContent -match '(?im)\bALTER\s+DATABASE\b') {
            throw "La migracion $($file.Name) contiene ALTER DATABASE. Requiere un procedimiento especifico fuera de este ejecutor."
        }

        $beginMatches = [regex]::Matches(
            $fileContent,
            '(?im)^\s*BEGIN\s*;'
        )

        $commitMatches = [regex]::Matches(
            $fileContent,
            '(?im)^\s*COMMIT\s*;'
        )

        if (
            ($beginMatches.Count -eq 0 -and $commitMatches.Count -ne 0) -or
            ($beginMatches.Count -ne 0 -and $commitMatches.Count -eq 0) -or
            $beginMatches.Count -gt 1 -or
            $commitMatches.Count -gt 1
        ) {
            throw "Estructura transaccional no compatible en $($file.Name)."
        }

        $escapedFile = $file.Name.Replace("'", "''")
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $payloadPath = $null

        Write-Host "[APLICANDO] $version ($($file.Name))..." -NoNewline

        $recordSql = @"
INSERT INTO public.schema_version
    (version, archivo, checksum, tiempo_ms)
VALUES
    ('$version', '$escapedFile', '$checksum', 0);
"@

        if ($beginMatches.Count -eq 1) {
            # Insertar bloqueo y registro dentro de la transaccion existente.
            $begin = $beginMatches[0]
            $commit = $commitMatches[0]

            if ($commit.Index -lt $begin.Index) {
                throw "COMMIT anterior a BEGIN en $($file.Name)."
            }

            $beforeBegin = $fileContent.Substring(0, $begin.Index + $begin.Length)
            $afterBegin = $fileContent.Substring($begin.Index + $begin.Length)
            $commitRelativeIndex = $commit.Index - ($begin.Index + $begin.Length)

            $body = $afterBegin.Substring(0, $commitRelativeIndex)
            $afterCommit = $afterBegin.Substring(
                $commitRelativeIndex + $commit.Length
            )

            $payload = "\set ON_ERROR_STOP on`n" +
                $beforeBegin +
                "`nSELECT pg_advisory_xact_lock(83726194);`n" +
                $body +
                "`n" + $recordSql + "`nCOMMIT;" +
                $afterCommit
        }
        else {
            # Migracion sin BEGIN/COMMIT: envolver DDL e historial atomicamente.
            $payload = @"
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(83726194);
$fileContent
$recordSql
COMMIT;
"@
        }

        try {
            # Ejecutar mediante archivo UTF-8 evita la conversión de stdin de
            # Windows PowerShell que puede sustituir caracteres Unicode por '?'.
            $payloadPath = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText(
                $payloadPath,
                $payload,
                [System.Text.UTF8Encoding]::new($false)
            )

            & psql -X --host=$DbHost --port=$Port `
                --username=$targetUser --dbname=$targetDb --no-password -q `
                --set=ON_ERROR_STOP=1 --file=$payloadPath
            $psqlExit = $LASTEXITCODE
        }
        finally {
            if ($null -ne $payloadPath) {
                Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
            }
            $stopwatch.Stop()
        }

        if ($psqlExit -ne 0) {
            Write-Host " [FALLO]" -ForegroundColor Red
            throw "Fallo en $($file.Name). PostgreSQL devolvio codigo $psqlExit."
        }

        $elapsedMs = [int]$stopwatch.ElapsedMilliseconds

        $appliedMap[$version] = @{
            Checksum   = $checksum
            Archivo    = $file.Name
            AplicadoEn = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        Write-Host " [OK] ($elapsedMs ms; registro transaccional en schema_version)" -ForegroundColor Green
        $appliedCount++
    }

    Write-Host "------------------------------------------------------------"
    Write-Host "Migraciones aplicadas en esta ejecucion: $appliedCount"
    Write-Host "Despliegue finalizado."
}
catch {
    $exitCode = 1
    Write-Host ""
    Write-Host "ERROR EN EL DESPLIEGUE: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($mutexAcquired -and $null -ne $mutex) {
        try {
            $mutex.ReleaseMutex()
        }
        catch {
            # No ocultar el error original durante la limpieza.
        }
    }

    if ($null -ne $mutex) {
        $mutex.Dispose()
    }

    if ($null -eq $oldPassword) {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    } else {
        $env:PGPASSWORD = $oldPassword
    }

    if ($null -eq $oldEncoding) {
        Remove-Item Env:PGCLIENTENCODING -ErrorAction SilentlyContinue
    } else {
        $env:PGCLIENTENCODING = $oldEncoding
    }
}

exit $exitCode
