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

function Get-WSLRepoPath {
    $WslPath = (& wsl --exec wslpath -a $ScriptDir).Trim()
    if (-not $WslPath) {
        throw "Could not convert repository path to a WSL path."
    }
    return $WslPath
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

New-Item -ItemType Directory -Force -Path "workspace" | Out-Null

if ($Mode -eq "WSLg") {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Error "wsl command not found. Enable WSL2 and WSLg first."
        exit 1
    }

    $WslRepoPath = Get-WSLRepoPath
    Write-Host "Using WSLg. Repository path in WSL: $WslRepoPath"

    Ensure-WSLDockerCompose

    Invoke-Native -Command "wsl" -Arguments @(
        "--exec",
        "bash",
        "-lc",
        "cd '$WslRepoPath' && sed -i 's/\r$//' run-wslg.sh setup-wslg.sh 2>/dev/null || true; chmod +x run-wslg.sh setup-wslg.sh 2>/dev/null || true; ./run-wslg.sh"
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
