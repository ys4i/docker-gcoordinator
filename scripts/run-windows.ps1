param(
    [ValidateSet("WSLg", "VcXsrv")]
    [string]$Mode = "WSLg"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
Set-Location $RepoDir

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
    $WslPathOutput = @(& wsl --exec wslpath -a $RepoDir)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not convert repository path '$RepoDir' to a WSL path."
    }
    $WslPath = ($WslPathOutput -join "").Trim()
    if (-not $WslPath) {
        throw "Could not convert repository path to a WSL path."
    }
    return $WslPath
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "wsl command not found. Run install-windows.ps1 first."
}

$WslRepoPath = Get-WSLRepoPath
$CommonPrefix = "if ! docker info >/dev/null 2>&1; then sudo -n /usr/sbin/service docker start; fi"

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
            "$CommonPrefix && sed -i 's/\r$//' scripts/run-wslg.sh && chmod +x scripts/run-wslg.sh && ./scripts/run-wslg.sh"
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
            "sed -i 's/\r$//' scripts/run-vcxsrv.sh && chmod +x scripts/run-vcxsrv.sh && ./scripts/run-vcxsrv.sh"
        ) `
        -ErrorMessage "VcXsrv application startup failed. Review the specific error above."
}
