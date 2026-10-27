param(
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'

$appPath = $PSScriptRoot
$apiPath = Join-Path (Split-Path $appPath -Parent) 'buid_arch_api'
$apiEnvPath = Join-Path $apiPath '.env'
$localPropertiesPath = Join-Path $appPath 'android\local.properties'

if (!(Test-Path $apiEnvPath)) {
    throw "Laravel environment file not found: $apiEnvPath"
}

$googleClientLine = Get-Content $apiEnvPath |
    Where-Object { $_ -match '^GOOGLE_WEB_CLIENT_ID=' } |
    Select-Object -First 1
$googleClientId = if ($googleClientLine) {
    ($googleClientLine -replace '^GOOGLE_WEB_CLIENT_ID=', '').Trim().Trim('"').Trim("'")
}
if (!$googleClientId) {
    throw 'Set GOOGLE_WEB_CLIENT_ID in buid_arch_api\.env before launching the app.'
}

$sdkLine = Get-Content $localPropertiesPath |
    Where-Object { $_ -match '^sdk\.dir=' } |
    Select-Object -First 1
if (!$sdkLine) {
    throw "Android SDK path is missing from $localPropertiesPath"
}
$sdkPath = ($sdkLine -replace '^sdk\.dir=', '').Replace('\\', '\')
$adbPath = Join-Path $sdkPath 'platform-tools\adb.exe'
if (!(Test-Path $adbPath)) {
    throw "Android Debug Bridge not found: $adbPath"
}

$connectedDevices = @(
    & $adbPath devices |
        Select-String '^\S+\s+device$' |
        ForEach-Object { ($_.Line -split '\s+')[0] }
)
if (!$DeviceId) {
    if ($connectedDevices.Count -ne 1) {
        throw 'Connect exactly one Android phone, or pass its serial with -DeviceId.'
    }
    $DeviceId = $connectedDevices[0]
}
if ($DeviceId -notin $connectedDevices) {
    throw "Android device '$DeviceId' is not connected or has not authorized USB debugging."
}

function Test-LocalApi {
    try {
        $response = Invoke-WebRequest `
            -Uri 'http://127.0.0.1:8000/api/user' `
            -Headers @{ Accept = 'application/json' } `
            -TimeoutSec 3 `
            -UseBasicParsing
        $statusCode = [int]$response.StatusCode
        return $statusCode -eq 200 -or $statusCode -eq 401
    } catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            return $statusCode -eq 200 -or $statusCode -eq 401
        }
        return $false
    }
}

if (!(Test-LocalApi)) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        throw 'Port 8000 is occupied, but the Laravel API did not respond. Stop the other service and retry.'
    }

    $php = Get-Command php -ErrorAction Stop
    $publicPath = Join-Path $apiPath 'public'
    $routerPath = Join-Path `
        $apiPath `
        'vendor\laravel\framework\src\Illuminate\Foundation\resources\server.php'
    $stdoutLog = Join-Path $env:TEMP 'buid_arch_api-server.out.log'
    $stderrLog = Join-Path $env:TEMP 'buid_arch_api-server.err.log'
    Start-Process `
        -FilePath $php.Source `
        -ArgumentList @(
            '-d', 'upload_max_filesize=100M',
            '-d', 'post_max_size=110M',
            '-d', 'max_input_time=600',
            '-d', 'max_execution_time=600',
            '-S', '127.0.0.1:8000',
            $routerPath
        ) `
        -WorkingDirectory $publicPath `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog | Out-Null

    $apiReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-LocalApi) {
            $apiReady = $true
            break
        }
    }
    if (!$apiReady) {
        throw "Laravel API did not become ready. Check $stderrLog and the Laravel log."
    }
}

& $adbPath -s $DeviceId reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) {
    throw 'Could not forward the API port to the phone. Reconnect the phone and authorize USB debugging.'
}

$flutter = Get-Command flutter -ErrorAction Stop
Write-Host "Launching Build Arch on $DeviceId. The local Laravel API is ready on port 8000."
Push-Location $appPath
try {
    & $flutter.Source run `
        -d $DeviceId `
        --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
        --dart-define="GOOGLE_WEB_CLIENT_ID=$googleClientId"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
