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

function Add-PathIfExists {
    param([string]$Path)

    if ((Test-Path $Path) -and ($env:Path -notlike "*$Path*")) {
        $env:Path = "$Path;$env:Path"
    }
}

function Refresh-ToolPath {
    Add-PathIfExists -Path (Join-Path $env:ProgramFiles "Docker\Docker\resources\bin")
    Add-PathIfExists -Path (Join-Path $env:ProgramFiles "Docker\Docker")
    Add-PathIfExists -Path (Join-Path $env:ProgramFiles "VcXsrv")
}

function Invoke-NativeQuiet {
    param(
        [string]$Command,
        [string[]]$Arguments = @()
    )

    try {
        $PreviousNativePreference = $null
        if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
            $PreviousNativePreference = $global:PSNativeCommandUseErrorActionPreference
            $global:PSNativeCommandUseErrorActionPreference = $false
        }

        & $Command @Arguments > $null 2> $null
        return $LASTEXITCODE
    }
    catch {
        return 1
    }
    finally {
        if ($null -ne $PreviousNativePreference) {
            $global:PSNativeCommandUseErrorActionPreference = $PreviousNativePreference
        }
    }
}

function Wait-DockerReady {
    Write-Host "Waiting for Docker daemon..."
    for ($i = 0; $i -lt 60; $i++) {
        if ((Invoke-NativeQuiet -Command "docker" -Arguments @("info")) -eq 0) {
            Write-Host "Docker daemon is ready."
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "Docker daemon did not become ready. Start Docker Desktop and re-run this script."
}

function Invoke-RequiredNative {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$ErrorMessage
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Ensure-DockerDesktop {
    if (-not (Test-Command docker)) {
        Install-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
        Refresh-ToolPath
    }

    if (-not (Test-Command docker)) {
        throw "docker command not found after installing Docker Desktop. Restart PowerShell, then re-run this script."
    }

    if ((Invoke-NativeQuiet -Command "docker" -Arguments @("compose", "version")) -ne 0) {
        throw "docker compose is not available. Check Docker Desktop installation."
    }

    if ((Invoke-NativeQuiet -Command "docker" -Arguments @("info")) -ne 0) {
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
        Refresh-ToolPath
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

function Get-DefaultWslDistro {
    $DefaultLine = wsl --list --verbose | Where-Object { $_ -match '^\s*\*' } | Select-Object -First 1
    if (-not $DefaultLine) {
        return $null
    }

    $DistroName = ($DefaultLine -replace '^\s*\*\s*', '') -replace '\s{2,}.*$', ''
    $DistroName = $DistroName.Trim()
    if ($DistroName) {
        return $DistroName
    }

    return $null
}

function Set-JsonProperty {
    param(
        [pscustomobject]$Object,
        [string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Enable-DockerDesktopWslIntegration {
    $DefaultDistro = Get-DefaultWslDistro
    if (-not $DefaultDistro) {
        Write-Host "Could not detect the default WSL distro. Skipping automatic Docker Desktop WSL integration update."
        return $false
    }

    $DockerSettingsDir = Join-Path $env:APPDATA "Docker"
    $SettingsStorePath = Join-Path $DockerSettingsDir "settings-store.json"
    $LegacySettingsPath = Join-Path $DockerSettingsDir "settings.json"
    $SettingsPath = $SettingsStorePath

    if ((-not (Test-Path $SettingsPath)) -and (Test-Path $LegacySettingsPath)) {
        $SettingsPath = $LegacySettingsPath
    }

    New-Item -ItemType Directory -Force -Path $DockerSettingsDir | Out-Null

    if (Test-Path $SettingsPath) {
        $Settings = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json
    }
    else {
        $Settings = [pscustomobject]@{}
    }

    $Changed = $false

    if ($Settings.PSObject.Properties.Name -notcontains "wslEngineEnabled" -or $Settings.wslEngineEnabled -ne $true) {
        Set-JsonProperty -Object $Settings -Name "wslEngineEnabled" -Value $true
        $Changed = $true
    }

    if ($Settings.PSObject.Properties.Name -notcontains "enableIntegrationWithDefaultWslDistro" -or $Settings.enableIntegrationWithDefaultWslDistro -ne $true) {
        Set-JsonProperty -Object $Settings -Name "enableIntegrationWithDefaultWslDistro" -Value $true
        $Changed = $true
    }

    $IntegratedDistros = @()
    if ($Settings.PSObject.Properties.Name -contains "integratedWslDistros" -and $null -ne $Settings.integratedWslDistros) {
        $IntegratedDistros = @($Settings.integratedWslDistros)
    }

    if ($IntegratedDistros -notcontains $DefaultDistro) {
        $IntegratedDistros += $DefaultDistro
        Set-JsonProperty -Object $Settings -Name "integratedWslDistros" -Value $IntegratedDistros
        $Changed = $true
    }

    if (-not $Changed) {
        return $false
    }

    if (Test-Path $SettingsPath) {
        $BackupPath = "$SettingsPath.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item -Path $SettingsPath -Destination $BackupPath
        Write-Host "Backed up Docker Desktop settings: $BackupPath"
    }

    $Settings | ConvertTo-Json -Depth 100 | Set-Content -Path $SettingsPath -Encoding UTF8
    Write-Host "Enabled Docker Desktop WSL integration for distro: $DefaultDistro"
    return $true
}

function Restart-DockerDesktopAndWsl {
    $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"

    Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    & wsl --shutdown > $null 2> $null

    if (Test-Path $DockerDesktop) {
        Write-Host "Starting Docker Desktop..."
        Start-Process $DockerDesktop | Out-Null
    }
}

function Test-WSLDockerCompose {
    return (Invoke-NativeQuiet -Command "wsl" -Arguments @("--exec", "bash", "-lc", "docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1")) -eq 0
}

function Ensure-WSLDockerCompose {
    if (Test-WSLDockerCompose) {
        return
    }

    Write-Host "Docker Compose is not available inside WSL. Trying to enable Docker Desktop WSL integration..."
    Enable-DockerDesktopWslIntegration | Out-Null
    Restart-DockerDesktopAndWsl

    for ($i = 0; $i -lt 60; $i++) {
        if (Test-WSLDockerCompose) {
            Write-Host "Docker Desktop WSL integration is ready."
            return
        }
        Start-Sleep -Seconds 2
    }

    throw "Docker Compose is still unavailable inside WSL. Open Docker Desktop Settings > Resources > WSL integration and enable the default distro, then re-run this script."
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

    Ensure-WSLDockerCompose
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
        Invoke-RequiredNative `
            -Command "docker" `
            -Arguments @("compose", "-f", "docker-compose.yml", "-f", "docker-compose.windows.yml", "build") `
            -ErrorMessage "Docker image build failed. Fix the build error above, then re-run this script."
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
        Invoke-RequiredNative `
            -Command "wsl" `
            -Arguments @("--exec", "bash", "-lc", "cd '$WslRepoPath' && if docker compose version >/dev/null 2>&1; then docker compose -f docker-compose.yml -f docker-compose.wslg.yml build; elif docker-compose version >/dev/null 2>&1; then docker-compose -f docker-compose.yml -f docker-compose.wslg.yml build; else echo 'Docker Compose is not available inside WSL. Enable Docker Desktop WSL integration for this distro, or install the Docker Compose plugin in WSL.' >&2; exit 1; fi") `
            -ErrorMessage "WSLg Docker image build failed. Fix the build error above, then re-run this script."
    }

    Write-Host "Windows WSLg setup checks completed."
    Write-Host "Open this repository inside WSL and run: ./run-wslg.sh"

    if ($Launch) {
        wsl --exec sh -lc "cd '$WslRepoPath' && ./run-wslg.sh"
    }
}
