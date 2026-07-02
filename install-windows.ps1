param(
    [ValidateSet("VcXsrv", "WSLg")]
    [string]$Mode = "VcXsrv",
    [switch]$NoLaunch,
    [switch]$ForceSetup
)

$ErrorActionPreference = "Stop"

$RepositoryUrl = "https://github.com/ys4i/docker-gcoordinator.git"
$InstallDir = if ($env:GCOORDINATOR_INSTALL_DIR) {
    $env:GCOORDINATOR_INSTALL_DIR
}
else {
    Join-Path $HOME "Projects\docker-gcoordinator"
}
$StateFile = Join-Path $env:LOCALAPPDATA "docker-gcoordinator\windows-$($Mode.ToLowerInvariant())-built-revision"
$Action = ""

function Refresh-GitPath {
    $Candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd")
    )
    foreach ($Candidate in $Candidates) {
        if ((Test-Path $Candidate) -and ($env:Path -notlike "*$Candidate*")) {
            $env:Path = "$Candidate;$env:Path"
        }
    }
}

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
    throw "This installer must be run on Windows."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Git is required and winget is unavailable. Install Git for Windows and retry."
    }
    Write-Host "Installing Git for Windows..."
    winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Git installation failed with exit code $LASTEXITCODE."
    }
    Refresh-GitPath
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was installed but is not available in PATH. Restart PowerShell and retry."
}

if (Test-Path (Join-Path $InstallDir ".git")) {
    $OriginUrl = (& git -C $InstallDir remote get-url origin 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $OriginUrl -notin @(
            "https://github.com/ys4i/docker-gcoordinator.git",
            "https://github.com/ys4i/docker-gcoordinator",
            "git@github.com:ys4i/docker-gcoordinator.git"
        )) {
        throw "$InstallDir exists but is not the expected repository. Current origin: $OriginUrl"
    }

    Write-Host "Updating the existing installation..."
    $PreviousRevision = (& git -C $InstallDir rev-parse HEAD | Out-String).Trim()
    & git -C $InstallDir pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "Could not update the existing repository."
    }
    $CurrentRevision = (& git -C $InstallDir rev-parse HEAD | Out-String).Trim()
    if ($PreviousRevision -ne $CurrentRevision) {
        $Action = "setup"
    }
}
elseif (Test-Path $InstallDir) {
    throw "$InstallDir already exists but is not a Git repository."
}
else {
    Write-Host "Installing docker-gcoordinator into $InstallDir..."
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallDir) | Out-Null
    & git clone $RepositoryUrl $InstallDir
    if ($LASTEXITCODE -ne 0) {
        throw "Repository clone failed."
    }
    $CurrentRevision = (& git -C $InstallDir rev-parse HEAD | Out-String).Trim()
    $Action = "setup"
}

$BuiltRevision = if (Test-Path $StateFile) {
    (Get-Content -Raw $StateFile).Trim()
}
else {
    ""
}

if ($ForceSetup -or
    $BuiltRevision -ne $CurrentRevision -or
    -not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    $Action = "setup"
}
elseif (-not $Action) {
    & wsl --exec bash -lc "docker info >/dev/null 2>&1 || sudo -n service docker start >/dev/null 2>&1; docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker image inspect docker-gcoordinator:latest >/dev/null 2>&1"
    if ($LASTEXITCODE -ne 0) {
        $Action = "setup"
    }
}

if ($Action -eq "setup") {
    Write-Host "Setup is required. Running setup-windows.ps1..."
    $SetupArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $InstallDir "scripts\setup-windows.ps1"),
        "-Mode", $Mode
    )
    if ($NoLaunch) {
        $SetupArguments += "-NoLaunch"
    }
    & powershell.exe @SetupArguments
    exit $LASTEXITCODE
}

if ($NoLaunch) {
    Write-Host "Installation is current. Nothing to do (-NoLaunch)."
    exit 0
}

Write-Host "Installation is current. Running run-windows.ps1..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $InstallDir "scripts\run-windows.ps1") -Mode $Mode
exit $LASTEXITCODE
