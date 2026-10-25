$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    throw 'Firebase CLI is required. Install it and run firebase login first.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidTemp = "android/app/google-services.$([guid]::NewGuid().ToString('N')).json"
$iosTemp = "ios/Runner/GoogleService-Info.$([guid]::NewGuid().ToString('N')).plist"
Push-Location $projectRoot
try {
    firebase apps:sdkconfig ANDROID '1:1077713975334:android:b93df4d24c8a1356e80ee7' --out $androidTemp --project assistummah
    if ($LASTEXITCODE -ne 0) { throw 'Could not download Android Firebase configuration.' }
    Copy-Item -LiteralPath $androidTemp -Destination android/app/google-services.json -Force

    firebase apps:sdkconfig IOS '1:1077713975334:ios:f367f1336f5c5acae80ee7' --out $iosTemp --project assistummah
    if ($LASTEXITCODE -ne 0) { throw 'Could not download iOS Firebase configuration.' }
    Copy-Item -LiteralPath $iosTemp -Destination ios/Runner/GoogleService-Info.plist -Force

    $androidConfig = Get-Content android/app/google-services.json -Raw | ConvertFrom-Json
    if ($androidConfig.client[0].oauth_client.Count -eq 0) {
        Write-Warning 'Android Google sign-in has no OAuth client yet. Add SHA-1 and SHA-256 fingerprints in Firebase, then run this script again.'
    }
    if (-not (Select-String -Path ios/Runner/GoogleService-Info.plist -Pattern '<key>CLIENT_ID</key>' -Quiet)) {
        Write-Warning 'iOS Google sign-in has no OAuth client yet. Configure it in Firebase before enabling the mobile Google button.'
    }
}
finally {
    Remove-Item -LiteralPath $androidTemp,$iosTemp -ErrorAction SilentlyContinue
    Pop-Location
}
