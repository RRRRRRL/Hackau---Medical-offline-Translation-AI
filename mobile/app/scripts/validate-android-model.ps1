[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$modelPath = Join-Path $appRoot 'android/app/src/main/assets/ggml-tiny.bin'
$metaPath = Join-Path $appRoot 'android/app/src/main/assets/ggml-tiny.metadata.json'

if (-not (Test-Path $modelPath)) {
    throw "Missing model asset: $modelPath"
}
if (-not (Test-Path $metaPath)) {
    throw "Missing metadata file: $metaPath"
}

$modelInfo = Get-Item $modelPath
if ($modelInfo.Length -le 0) {
    throw 'Model file is empty.'
}

$probe = Get-Content -Path $modelPath -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue
if ($probe -and ($probe -match '<html' -or $probe -match '<!DOCTYPE')) {
    throw 'Model file appears to contain HTML content, not binary weights.'
}

$metadata = Get-Content -Path $metaPath -Raw | ConvertFrom-Json
if (-not $metadata.sha256) {
    throw 'Metadata missing sha256 value.'
}
if (-not $metadata.source) {
    throw 'Metadata missing source URL.'
}
if ($metadata.source -notmatch '^https://huggingface.co/ggerganov/whisper.cpp/') {
    throw "Metadata source is not official whisper.cpp URL: $($metadata.source)"
}

$actualHash = (Get-FileHash -Path $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $metadata.sha256.ToString().ToLowerInvariant()) {
    throw "Checksum mismatch. expected=$($metadata.sha256) actual=$actualHash"
}

Write-Host 'Model validation passed.'
Write-Host "Path: $modelPath"
Write-Host "SHA256: $actualHash"
Write-Host "Source: $($metadata.source)"
