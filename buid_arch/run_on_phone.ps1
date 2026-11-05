param(
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'

$appPath = $PSScriptRoot
$apiPath = Join-Path (Split-Path $appPath -Parent) 'buid_arch_api'
$apiEnvPath = Join-Path $apiPath '.env'
$localPropertiesPath = Join-Path $appPath 'android\local.properties'
$apiPort = 8000
$reverbPort = 8080
$reverbHost = '127.0.0.1'
$apiBaseUrl = "http://127.0.0.1:$apiPort/api"

if (!(Test-Path $apiEnvPath)) {
    throw "Laravel environment file not found: $apiEnvPath"
}

function Get-ApiEnvironmentValue([string]$Name) {
    $line = Get-Content $apiEnvPath |
        Where-Object { $_ -match "^$([regex]::Escape($Name))=" } |
        Select-Object -Last 1
    if (!$line) {
        return ''
    }

    return ($line -replace "^$([regex]::Escape($Name))=", '').Trim().Trim('"').Trim("'")
}

$firebaseProjectId = Get-ApiEnvironmentValue 'FIREBASE_PROJECT_ID'
$firebaseApiKey = Get-ApiEnvironmentValue 'FIREBASE_API_KEY'
$firebaseSenderId = Get-ApiEnvironmentValue 'FIREBASE_MESSAGING_SENDER_ID'
$firebaseAndroidAppId = Get-ApiEnvironmentValue 'FIREBASE_ANDROID_APP_ID'
$firebaseIosAppId = Get-ApiEnvironmentValue 'FIREBASE_IOS_APP_ID'
$firebaseStorageBucket = Get-ApiEnvironmentValue 'FIREBASE_STORAGE_BUCKET'

$googleClientLine = Get-Content $apiEnvPath |
    Where-Object { $_ -match '^GOOGLE_WEB_CLIENT_ID=' } |
    Select-Object -First 1
$googleClientId = if ($googleClientLine) {
    ($googleClientLine -replace '^GOOGLE_WEB_CLIENT_ID=', '').Trim().Trim('"').Trim("'")
}
if (!$googleClientId) {
    throw 'Set GOOGLE_WEB_CLIENT_ID in buid_arch_api\.env before launching the app.'
}
$reverbKeyLine = Get-Content $apiEnvPath |
    Where-Object { $_ -match '^REVERB_APP_KEY=' } |
    Select-Object -Last 1
$reverbAppKey = if ($reverbKeyLine) {
    ($reverbKeyLine -replace '^REVERB_APP_KEY=', '').Trim().Trim('"').Trim("'")
}
if (!$reverbAppKey) {
    throw 'Set REVERB_APP_KEY in buid_arch_api\.env before launching the app.'
}
$broadcastLine = Get-Content $apiEnvPath |
    Where-Object { $_ -match '^BROADCAST_CONNECTION=' } |
    Select-Object -Last 1
$broadcastDriver = if ($broadcastLine) {
    ($broadcastLine -replace '^BROADCAST_CONNECTION=', '').Trim().Trim('"').Trim("'")
}
if ($broadcastDriver -ne 'reverb') {
    throw 'Set BROADCAST_CONNECTION=reverb in buid_arch_api\.env for live chat.'
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
            -Uri "$apiBaseUrl/user" `
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

function Test-LocalTcpPort([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $Port)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

if (!(Test-LocalApi)) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $apiPort -ErrorAction SilentlyContinue |
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
            '-S', "127.0.0.1:$apiPort",
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

if (!(Test-LocalTcpPort $reverbPort)) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $reverbPort -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        throw 'Port 8080 is occupied, but the Reverb chat server did not respond.'
    }

    $php = Get-Command php -ErrorAction Stop
    $stdoutLog = Join-Path $env:TEMP 'buid_arch_reverb-server.out.log'
    $stderrLog = Join-Path $env:TEMP 'buid_arch_reverb-server.err.log'
    Start-Process `
        -FilePath $php.Source `
        -ArgumentList @(
            'artisan',
            'reverb:start',
            '--host=127.0.0.1',
            "--port=$reverbPort",
            '--no-interaction'
        ) `
        -WorkingDirectory $apiPath `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog | Out-Null

    $reverbReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-LocalTcpPort $reverbPort) {
            $reverbReady = $true
            break
        }
    }
    if (!$reverbReady) {
        throw "Laravel Reverb did not become ready. Check $stderrLog and the Laravel log."
    }
}

$queueConnection = Get-ApiEnvironmentValue 'QUEUE_CONNECTION'
if (!$queueConnection) {
    $queueConnection = 'database'
}
if ($queueConnection -ne 'sync') {
    $queueWorker = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^php(?:\.exe)?$' -and
            $_.CommandLine -match 'artisan\s+queue:work' -and
            $_.CommandLine -match '--queue=notifications,default'
        } |
        Select-Object -First 1

    if (!$queueWorker) {
        $php = Get-Command php -ErrorAction Stop
        $stdoutLog = Join-Path $env:TEMP 'buid_arch_queue-worker.out.log'
        $stderrLog = Join-Path $env:TEMP 'buid_arch_queue-worker.err.log'
        $queueWorkerProcess = Start-Process `
            -FilePath $php.Source `
            -ArgumentList @(
                'artisan',
                'queue:work',
                '--queue=notifications,default',
                '--tries=3',
                '--sleep=3',
                '--no-interaction'
            ) `
            -WorkingDirectory $apiPath `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -PassThru
        Start-Sleep -Seconds 1
        if (!(Get-Process -Id $queueWorkerProcess.Id -ErrorAction SilentlyContinue)) {
            throw "Laravel queue worker did not start. Check $stderrLog."
        }
    }
}

& $adbPath -s $DeviceId reverse "tcp:$apiPort" "tcp:$apiPort"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not forward the API port to the phone. Reconnect the phone and authorize USB debugging.'
}
$reverseMappings = & $adbPath -s $DeviceId reverse --list
if ($LASTEXITCODE -ne 0 -or
    !($reverseMappings | Select-String -Quiet "tcp:$apiPort tcp:$apiPort")) {
    throw 'The API port forwarding could not be verified. Reconnect the phone and retry.'
}
& $adbPath -s $DeviceId reverse "tcp:$reverbPort" "tcp:$reverbPort"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not forward the chat port to the phone. Reconnect the phone and authorize USB debugging.'
}
$reverseMappings = & $adbPath -s $DeviceId reverse --list
if ($LASTEXITCODE -ne 0 -or
    !($reverseMappings | Select-String -Quiet "tcp:$reverbPort tcp:$reverbPort")) {
    throw 'The chat port forwarding could not be verified. Reconnect the phone and retry.'
}

$flutter = Get-Command flutter -ErrorAction Stop
Write-Host "Launching Build Arch on $DeviceId. The local Laravel API is ready on port 8000."
if (!$firebaseApiKey -or !$firebaseProjectId -or !$firebaseSenderId -or
    !$firebaseAndroidAppId) {
    Write-Host 'Firebase client configuration is incomplete; device push registration will be disabled.'
}
Push-Location $appPath
try {
    & $flutter.Source run `
        -d $DeviceId `
        "--dart-define=API_BASE_URL=$apiBaseUrl" `
        --dart-define="GOOGLE_WEB_CLIENT_ID=$googleClientId" `
        "--dart-define=REVERB_APP_KEY=$reverbAppKey" `
        "--dart-define=REVERB_HOST=$reverbHost" `
        "--dart-define=REVERB_PORT=$reverbPort" `
        --dart-define=REVERB_SCHEME=http `
        "--dart-define=FIREBASE_PROJECT_ID=$firebaseProjectId" `
        "--dart-define=FIREBASE_API_KEY=$firebaseApiKey" `
        "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$firebaseSenderId" `
        "--dart-define=FIREBASE_ANDROID_APP_ID=$firebaseAndroidAppId" `
        "--dart-define=FIREBASE_IOS_APP_ID=$firebaseIosAppId" `
        "--dart-define=FIREBASE_STORAGE_BUCKET=$firebaseStorageBucket" `
        --dart-define=FIREBASE_IOS_BUNDLE_ID=com.buidarch.buidArch
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
