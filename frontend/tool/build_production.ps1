[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Web', 'Android', 'AndroidApk')]
    [string]$Target,

    [string]$ApiBaseUrl = 'https://api.mushukistan.uz/api/v1/',

    [string]$GoogleWebClientId = $env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID,

    [switch]$EnableAndroidPush
)

$ErrorActionPreference = 'Stop'

$expectedApiBaseUrl = 'https://api.mushukistan.uz/api/v1/'
$normalizedApiBaseUrl = $ApiBaseUrl.Trim().TrimEnd('/') + '/'
if ($normalizedApiBaseUrl -ne $expectedApiBaseUrl) {
    throw "Production releases must use $expectedApiBaseUrl as MUSHUKISTAN_API_BASE_URL."
}

if ([string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
    throw 'Set MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID before building a production release.'
}
$normalizedGoogleClientId = $GoogleWebClientId.Trim()
if ($normalizedGoogleClientId -notmatch '^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$') {
    throw 'MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID is not a valid Google OAuth client ID.'
}

$frontendRoot = Split-Path -Parent $PSScriptRoot
if ($Target -eq 'Web' -and $EnableAndroidPush) {
    throw 'Android push cannot be enabled for Web.'
}
Push-Location $frontendRoot
try {
    if ($Target -eq 'Web') {
        # Keep CanvasKit on the same origin. This avoids Safari/WebKit startup
        # failures when the remote gstatic CanvasKit CDN is blocked or cannot
        # complete its WebAssembly load.
        & flutter build web --release --no-web-resources-cdn `
            "--dart-define=MUSHUKISTAN_API_BASE_URL=$normalizedApiBaseUrl" `
            "--dart-define=MUSHUKISTAN_GOOGLE_CLIENT_ID=$normalizedGoogleClientId"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter production web build failed with exit code $LASTEXITCODE."
        }

        $webBundle = Join-Path $frontendRoot 'build/web/main.dart.js'
        if (-not (Test-Path -LiteralPath $webBundle -PathType Leaf)) {
            throw 'Production web build did not create build/web/main.dart.js.'
        }
        $webContents = Get-Content -LiteralPath $webBundle -Raw
        if (-not $webContents.Contains('https://api.mushukistan.uz/api/v1/')) {
            throw 'Production web artifact does not contain the canonical API base URL.'
        }
        if (-not $webContents.Contains($normalizedGoogleClientId)) {
            throw 'Production web artifact does not contain the configured Google web client ID.'
        }
        $bootstrap = Join-Path $frontendRoot 'build/web/flutter_bootstrap.js'
        if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
            throw 'Production web build did not create build/web/flutter_bootstrap.js.'
        }
        $bootstrapContents = Get-Content -LiteralPath $bootstrap -Raw
        if (-not $bootstrapContents.Contains('"useLocalCanvasKit":true')) {
            throw 'Production web artifact is not configured to load CanvasKit locally.'
        }
        if (-not $bootstrapContents.Contains('retireLegacyFlutterServiceWorker')) {
            throw 'Production web artifact is missing legacy service-worker cleanup.'
        }
        if (-not $bootstrapContents.Contains('flutter-first-frame')) {
            throw 'Production web artifact is missing first-frame startup handling.'
        }
        if ($webContents.Contains('http://localhost') -or
            $webContents.Contains('http://10.0.2.2')) {
            throw 'Production web artifact contains a development API host.'
        }
        Write-Output 'Production web artifact configuration verified.'
        return
    }

    $keyProperties = Join-Path $frontendRoot 'android/key.properties'
    if (-not (Test-Path -LiteralPath $keyProperties -PathType Leaf)) {
        throw 'Android production release requires android/key.properties.'
    }

    if ($EnableAndroidPush) {
        $firebasePath = Join-Path $frontendRoot 'android/app/google-services.json'
        if (-not (Test-Path -LiteralPath $firebasePath -PathType Leaf)) {
            throw 'Push-enabled builds require frontend/android/app/google-services.json.'
        }
        $firebaseConfig = Get-Content -LiteralPath $firebasePath -Raw | ConvertFrom-Json
        $firebaseClients = @($firebaseConfig.client | Where-Object {
            $_.client_info.android_client_info.package_name -eq 'uz.mushukistan.app'
        })
        if ($firebaseClients.Count -ne 1) {
            throw 'Firebase configuration must contain exactly one uz.mushukistan.app Android client.'
        }
    }
    $androidArtifact = if ($Target -eq 'AndroidApk') { 'apk' } else { 'appbundle' }
    $pushBuildArguments = @()
    if ($EnableAndroidPush) {
        $pushBuildArguments = @('--dart-define=ENABLE_ANDROID_PUSH=true')
    }
    & flutter build $androidArtifact --release `
        "--dart-define=MUSHUKISTAN_API_BASE_URL=$normalizedApiBaseUrl" `
        "--dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=$normalizedGoogleClientId" @pushBuildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter production Android build failed with exit code $LASTEXITCODE."
    }

    $appBundle = Join-Path $frontendRoot $(if ($Target -eq 'AndroidApk') {
        'build/app/outputs/flutter-apk/app-release.apk'
    } else { 'build/app/outputs/bundle/release/app-release.aab' })
    if (-not (Test-Path -LiteralPath $appBundle -PathType Leaf)) {
        throw 'Android production build did not create the requested artifact.'
    }
    Write-Output "Production Android $androidArtifact created with explicit release configuration; push enabled: $EnableAndroidPush."
} finally {
    Pop-Location
}
