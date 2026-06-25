$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker command not found."
    exit 1
}

docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose is not available."
    exit 1
}

New-Item -ItemType Directory -Force -Path "workspace" | Out-Null

if (-not $env:DISPLAY) {
    $env:DISPLAY = "host.docker.internal:0.0"
}

if (-not $env:UID) {
    $env:UID = "1000"
}

if (-not $env:GID) {
    $env:GID = "1000"
}

Write-Host "DISPLAY=$env:DISPLAY"
Write-Host "Using Windows X server. Make sure VcXsrv or X410 is already running."

docker compose -f docker-compose.yml -f docker-compose.windows.yml run --rm gcoordinator
