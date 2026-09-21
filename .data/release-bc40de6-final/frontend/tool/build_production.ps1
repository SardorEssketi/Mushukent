[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Web', 'Android')]
    [string]$Target,

    [string]$ApiBaseUrl = 'https://api.mushukistan.uz/api/v1/',

    [string]$GoogleWebClientId = $env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID
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
Push-Location $frontendRoot
try {
    if ($Target -eq 'Web') {
        & flutter build web --release `
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

    & flutter build appbundle --release `
        "--dart-define=MUSHUKISTAN_API_BASE_URL=$normalizedApiBaseUrl" `
        "--dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=$normalizedGoogleClientId"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter production AAB build failed with exit code $LASTEXITCODE."
    }

    $appBundle = Join-Path $frontendRoot 'build/app/outputs/bundle/release/app-release.aab'
    if (-not (Test-Path -LiteralPath $appBundle -PathType Leaf)) {
        throw 'Android production build did not create app-release.aab.'
    }
    Write-Output 'Production Android App Bundle created with explicit release configuration.'
} finally {
    Pop-Location
}
