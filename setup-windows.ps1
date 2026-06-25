param(
    [ValidateSet("VcXsrv", "WSLg")]
    [string]$Mode = "VcXsrv",
    [switch]$SkipInstall,
    [switch]$NoBuild,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    if ($SkipInstall) {
        Write-Host "$Name is missing. Re-run without -SkipInstall to install it."
        return
    }

    if (-not (Test-Command winget)) {
        throw "winget is not available. Install $Name manually, then re-run with -SkipInstall."
    }

    Write-Host "Installing $Name with winget..."
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
}

function Wait-DockerReady {
    Write-Host "Waiting for Docker daemon..."
    for ($i = 0; $i -lt 60; $i++) {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker daemon is ready."
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "Docker daemon did not become ready. Start Docker Desktop and re-run this script."
}

function Ensure-DockerDesktop {
    if (-not (Test-Command docker)) {
        Install-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
    }

    if (-not (Test-Command docker)) {
        throw "docker command not found. Restart PowerShell after installing Docker Desktop."
    }

    docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose is not available. Check Docker Desktop installation."
    }

    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if (Test-Path $DockerDesktop) {
            Write-Host "Starting Docker Desktop..."
            Start-Process $DockerDesktop | Out-Null
        }
        Wait-DockerReady
    }
}

function Ensure-VcXsrv {
    $XLaunch = Join-Path $env:ProgramFiles "VcXsrv\xlaunch.exe"
    $VcXsrv = Join-Path $env:ProgramFiles "VcXsrv\vcxsrv.exe"

    if (-not (Test-Path $VcXsrv)) {
        Install-WingetPackage -Id "marha.VcXsrv" -Name "VcXsrv"
    }

    if (-not (Test-Path $VcXsrv)) {
        throw "VcXsrv was not found. Install it manually or use -Mode WSLg."
    }

    if (-not (Get-Process vcxsrv -ErrorAction SilentlyContinue)) {
        Write-Host "Starting VcXsrv on display :0..."
        Start-Process $VcXsrv -ArgumentList ":0 -multiwindow -clipboard -ac -wgl"
        Start-Sleep -Seconds 2
    }
}

function Ensure-WSLg {
    if (-not (Test-Command wsl)) {
        throw "wsl command not found. Enable WSL first."
    }

    wsl --status
    if ($LASTEXITCODE -ne 0) {
        if ($SkipInstall) {
            throw "WSL is not configured. Re-run without -SkipInstall or install WSL manually."
        }
        Write-Host "Installing WSL. A reboot may be required."
        wsl --install
        throw "WSL install was started. Reboot if requested, then run this script again."
    }

    wsl --exec sh -lc "test -d /mnt/wslg && test -e /dev/dxg && test -d /usr/lib/wsl/lib"
    if ($LASTEXITCODE -ne 0) {
        throw "WSLg GPU prerequisites are not available inside WSL. Update WSL and GPU drivers, then retry."
    }
}

function Get-WSLRepoPath {
    $WindowsPath = (Get-Location).Path
    $WslPath = (wsl --exec wslpath -a "$WindowsPath").Trim()
    if (-not $WslPath) {
        throw "Could not convert repository path to a WSL path."
    }
    return $WslPath
}

New-Item -ItemType Directory -Force -Path "workspace" | Out-Null
New-Item -ItemType Directory -Force -Path "log" | Out-Null

if ($Mode -eq "VcXsrv") {
    Ensure-DockerDesktop
    Ensure-VcXsrv

    $env:DISPLAY = "host.docker.internal:0.0"
    $env:UID = "1000"
    $env:GID = "1000"

    if (-not $NoBuild) {
        docker compose -f docker-compose.yml -f docker-compose.windows.yml build
    }

    Write-Host "Windows VcXsrv setup completed."
    Write-Host "Run: .\run-windows.ps1"

    if ($Launch) {
        .\run-windows.ps1
    }
}
else {
    Ensure-DockerDesktop
    Ensure-WSLg
    $WslRepoPath = Get-WSLRepoPath

    if (-not $NoBuild) {
        wsl --exec sh -lc "cd '$WslRepoPath' && docker compose -f docker-compose.yml -f docker-compose.wslg.yml build"
    }

    Write-Host "Windows WSLg setup checks completed."
    Write-Host "Open this repository inside WSL and run: ./run-wslg.sh"

    if ($Launch) {
        wsl --exec sh -lc "cd '$WslRepoPath' && ./run-wslg.sh"
    }
}
