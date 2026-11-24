$ErrorActionPreference = 'Stop'

$appPath = $PSScriptRoot
$androidPath = Join-Path $appPath 'android'
$gradlePath = Join-Path $androidPath 'app\build.gradle.kts'
$googleServicesPath = Join-Path $androidPath 'app\google-services.json'
$releaseSigningPath = Join-Path $androidPath 'release-key.properties'
$expectedApplicationId = 'com.buildarchsolutions.buildarch'

$requiredEnvironment = @(
    'BUILDARCH_PROD_FIREBASE_PROJECT_ID',
    'BUILDARCH_PROD_GOOGLE_WEB_CLIENT_ID',
    'BUILDARCH_PROD_REVERB_APP_KEY'
)
$missingEnvironment = @(
    $requiredEnvironment | Where-Object {
        [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
    }
)
if ($missingEnvironment.Count -gt 0) {
    throw "Set the required production settings before building: $($missingEnvironment -join ', ')."
}

if (!(Test-Path $releaseSigningPath)) {
    throw 'Production signing is not configured. Create android\release-key.properties and its keystore outside source control.'
}
if (!(Test-Path $googleServicesPath)) {
    throw 'Android Firebase configuration is missing: android\app\google-services.json.'
}

$gradle = Get-Content $gradlePath -Raw
$applicationIdMatch = [regex]::Match(
    $gradle,
    'applicationId\s*=\s*"([^"]+)"'
)
if (!$applicationIdMatch.Success) {
    throw 'Could not determine the Android applicationId from app/build.gradle.kts.'
}
$applicationId = $applicationIdMatch.Groups[1].Value
if ($applicationId -ne $expectedApplicationId) {
    throw 'The Android applicationId must be com.buildarchsolutions.buildarch.'
}
$namespaceMatch = [regex]::Match(
    $gradle,
    'namespace\s*=\s*"([^"]+)"'
)
if (!$namespaceMatch.Success -or
    $namespaceMatch.Groups[1].Value -ne $expectedApplicationId) {
    throw 'The Android namespace must match com.buildarchsolutions.buildarch.'
}

$googleServices = Get-Content $googleServicesPath -Raw | ConvertFrom-Json
$firebaseProjectId = $googleServices.project_info.project_id
if (!$firebaseProjectId -or
    $firebaseProjectId -ne $env:BUILDARCH_PROD_FIREBASE_PROJECT_ID) {
    throw 'google-services.json does not match BUILDARCH_PROD_FIREBASE_PROJECT_ID.'
}

$androidClient = $googleServices.client |
    Where-Object {
        $_.client_info.android_client_info.package_name -eq $applicationId
    } |
    Select-Object -First 1
if (!$androidClient) {
    throw 'google-services.json has no client matching the Android applicationId.'
}

$apiKeyEntry = $androidClient.api_key |
    Where-Object { ![string]::IsNullOrWhiteSpace($_.current_key) } |
    Select-Object -First 1
$firebaseApiKey = if ($apiKeyEntry) { $apiKeyEntry.current_key } else { '' }
$firebaseAndroidAppId = $androidClient.client_info.mobilesdk_app_id
$firebaseMessagingSenderId = $googleServices.project_info.project_number
$firebaseStorageBucket = $googleServices.project_info.storage_bucket
if (!$firebaseApiKey -or
    !$firebaseAndroidAppId -or
    !$firebaseMessagingSenderId) {
    throw 'google-services.json is missing required Android Firebase client settings.'
}

$flutter = Get-Command flutter -ErrorAction Stop
$apiBaseUrl = 'https://api.buildarchsolutions.com/api/'
$reverbHost = 'ws.buildarchsolutions.com'

$dartDefines = @(
    "--dart-define=API_BASE_URL=$apiBaseUrl"
    "--dart-define=REVERB_APP_KEY=$env:BUILDARCH_PROD_REVERB_APP_KEY"
    "--dart-define=REVERB_HOST=$reverbHost"
    '--dart-define=REVERB_PORT=443'
    '--dart-define=REVERB_SCHEME=https'
    "--dart-define=GOOGLE_WEB_CLIENT_ID=$env:BUILDARCH_PROD_GOOGLE_WEB_CLIENT_ID"
    "--dart-define=FIREBASE_PROJECT_ID=$firebaseProjectId"
    "--dart-define=FIREBASE_API_KEY=$firebaseApiKey"
    "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$firebaseMessagingSenderId"
    "--dart-define=FIREBASE_ANDROID_APP_ID=$firebaseAndroidAppId"
    "--dart-define=FIREBASE_STORAGE_BUCKET=$firebaseStorageBucket"
)

Push-Location $appPath
try {
    & $flutter.Source pub get
    if ($LASTEXITCODE -ne 0) {
        throw 'flutter pub get failed.'
    }

    $arguments = @('build', 'appbundle', '--release', '--no-pub') + $dartDefines
    & $flutter.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        throw 'The production Android App Bundle build failed.'
    }
    Write-Host 'Production App Bundle created at build\app\outputs\bundle\release\app-release.aab.'
} finally {
    Pop-Location
}
