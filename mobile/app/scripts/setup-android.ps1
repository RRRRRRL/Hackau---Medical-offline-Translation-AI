[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
Push-Location $appRoot
try {
    Write-Host 'Running npm ci in mobile/app...'
    npm ci

    Write-Host 'Downloading ggml-tiny.bin into Android assets...'
    & (Join-Path $scriptRoot 'setup-android-model.ps1')

    Write-Host 'Validating downloaded model asset...'
    & (Join-Path $scriptRoot 'validate-android-model.ps1')
} finally {
    Pop-Location
}
