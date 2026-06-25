param(
    [ValidateSet("WSLg", "VcXsrv")]
    [string]$Mode = "WSLg"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Invoke-Native {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Get-WSLRepoPath {
    $WslPath = (& wsl --exec wslpath -a $ScriptDir).Trim()
    if (-not $WslPath) {
        throw "Could not convert repository path to a WSL path."
    }
    return $WslPath
}

New-Item -ItemType Directory -Force -Path "workspace" | Out-Null

if ($Mode -eq "WSLg") {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Error "wsl command not found. Enable WSL2 and WSLg first."
        exit 1
    }

    $WslRepoPath = Get-WSLRepoPath
    Write-Host "Using WSLg. Repository path in WSL: $WslRepoPath"

    Invoke-Native -Command "wsl" -Arguments @(
        "--exec",
        "bash",
        "-lc",
        "cd '$WslRepoPath' && ./run-wslg.sh"
    )
}
else {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "docker command not found."
        exit 1
    }

    docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "docker compose is not available."
        exit 1
    }

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

    Invoke-Native -Command "docker" -Arguments @(
        "compose",
        "-f",
        "docker-compose.yml",
        "-f",
        "docker-compose.windows.yml",
        "run",
        "--rm",
        "gcoordinator"
    )
}
