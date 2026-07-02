param(
    [ValidateSet("WSLg", "VcXsrv")]
    [string]$Mode = "WSLg"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Invoke-RequiredNative {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$ErrorMessage
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Get-WSLRepoPath {
    $WslPathOutput = @(& wsl --exec wslpath -a $ScriptDir)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not convert repository path '$ScriptDir' to a WSL path."
    }
    $WslPath = ($WslPathOutput -join "").Trim()
    if (-not $WslPath) {
        throw "Could not convert repository path to a WSL path."
    }
    return $WslPath
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "wsl command not found. Run setup-windows.ps1 first."
}

$WslRepoPath = Get-WSLRepoPath
$CommonPrefix = "if ! docker info >/dev/null 2>&1; then sudo -n service docker start; fi"

if ($Mode -eq "WSLg") {
    Write-Host "Starting the application with WSLg and Docker Engine in WSL..."
    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @(
            "--cd",
            $WslRepoPath,
            "--exec",
            "bash",
            "-lc",
            "$CommonPrefix && sed -i 's/\r$//' run-wslg.sh && chmod +x run-wslg.sh && ./run-wslg.sh"
        ) `
        -ErrorMessage "WSLg application startup failed."
}
else {
    Write-Host "Starting the application with VcXsrv and Docker Engine in WSL..."
    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @(
            "--cd",
            $WslRepoPath,
            "--exec",
            "bash",
            "-lc",
            "$CommonPrefix && WINDOWS_HOST=`$(awk '/^nameserver / { print `$2; exit }' /etc/resolv.conf) && test -n `"`$WINDOWS_HOST`" && export DISPLAY=`"`$WINDOWS_HOST`:0.0`" && echo `"DISPLAY=`$DISPLAY`" && env UID=`$(id -u) GID=`$(id -g) docker compose -f docker-compose.yml -f docker-compose.windows.yml run --rm gcoordinator"
        ) `
        -ErrorMessage "VcXsrv application startup failed. Verify that VcXsrv is running with access control disabled."
}
