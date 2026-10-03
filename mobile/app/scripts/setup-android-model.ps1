[CmdletBinding()]
param(
    [string]$ModelUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true'
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$assetsDir = Join-Path $appRoot 'android/app/src/main/assets'
$modelPath = Join-Path $assetsDir 'ggml-tiny.bin'
$metaPath = Join-Path $assetsDir 'ggml-tiny.metadata.json'
$tmpPath = Join-Path $assetsDir ('ggml-tiny.bin.tmp-' + [guid]::NewGuid().ToString('N'))

if ($ModelUrl -notmatch '^https://huggingface.co/ggerganov/whisper.cpp/') {
    throw "ModelUrl must point to the official ggerganov/whisper.cpp repository. Got: $ModelUrl"
}

New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

Write-Host "Downloading multilingual ggml-tiny.bin from $ModelUrl"
Invoke-WebRequest -Uri $ModelUrl -OutFile $tmpPath -MaximumRedirection 5

if (-not (Test-Path $tmpPath)) {
    throw 'Download failed: temporary file was not created.'
}

$fileInfo = Get-Item $tmpPath
if ($fileInfo.Length -le 0) {
    Remove-Item -Force $tmpPath
    throw 'Download failed: ggml-tiny.bin is empty.'
}

$probe = Get-Content -Path $tmpPath -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue
if ($probe -and ($probe -match '<html' -or $probe -match '<!DOCTYPE')) {
    Remove-Item -Force $tmpPath
    throw 'Download failed: received HTML instead of model binary.'
}

$hash = (Get-FileHash -Path $tmpPath -Algorithm SHA256).Hash.ToLowerInvariant()

Move-Item -Path $tmpPath -Destination $modelPath -Force

$metadata = [ordered]@{
    source = $ModelUrl
    sha256 = $hash
    bytes = (Get-Item $modelPath).Length
    downloaded_at_utc = [DateTime]::UtcNow.ToString('o')
}
$metadata | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8

Write-Host "Model saved: $modelPath"
Write-Host "SHA256: $hash"
Write-Host "Metadata saved: $metaPath"
