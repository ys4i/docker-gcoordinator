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

$SetupProgressId = 1
$WaitProgressId = 2

function Write-SetupProgress {
    param(
        [int]$Percent,
        [string]$Status
    )

    Write-Progress `
        -Id $SetupProgressId `
        -Activity "Windows setup ($Mode)" `
        -Status $Status `
        -PercentComplete $Percent
    Write-Host "[$Percent%] $Status"
}

function Write-WaitProgress {
    param(
        [string]$Activity,
        [int]$Attempt,
        [int]$MaximumAttempts
    )

    Write-Progress `
        -Id $WaitProgressId `
        -ParentId $SetupProgressId `
        -Activity $Activity `
        -Status "Attempt $Attempt of $MaximumAttempts" `
        -PercentComplete ([math]::Min(100, [math]::Floor(($Attempt / $MaximumAttempts) * 100)))
}

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
    if ($Id -eq "Docker.DockerDesktop") {
        winget install `
            --id $Id `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --override "install --quiet --accept-license --backend=wsl-2"
    }
    else {
        winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    }

    if ($LASTEXITCODE -ne 0) {
        throw "$Name installation failed with exit code $LASTEXITCODE."
    }
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

function Test-DockerDaemon {
    param([int]$TimeoutSeconds = 5)

    $StdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) "docker-info-$PID-$([guid]::NewGuid().ToString('N')).out"
    $StderrPath = Join-Path ([System.IO.Path]::GetTempPath()) "docker-info-$PID-$([guid]::NewGuid().ToString('N')).err"
    $Process = $null

    try {
        $Process = Start-Process `
            -FilePath "docker" `
            -ArgumentList @("info") `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $StdoutPath `
            -RedirectStandardError $StderrPath

        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            $Process.Kill()
            $Process.WaitForExit()
            return $false
        }

        return $Process.ExitCode -eq 0
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $Process) {
            $Process.Dispose()
        }
        Remove-Item -Path $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Wait-DockerReady {
    $MaximumAttempts = 24
    Write-Host "Waiting up to 2 minutes for Docker daemon..."
    for ($i = 0; $i -lt $MaximumAttempts; $i++) {
        $Attempt = $i + 1
        Write-Host "[Docker] Checking daemon ($Attempt/$MaximumAttempts)..."
        if (Test-DockerDaemon -TimeoutSeconds 3) {
            Write-Progress -Id $WaitProgressId -ParentId $SetupProgressId -Activity "Waiting for Docker daemon" -Completed
            Write-Host "Docker daemon is ready."
            return
        }
        Write-WaitProgress -Activity "Waiting for Docker daemon" -Attempt $Attempt -MaximumAttempts $MaximumAttempts
        Start-Sleep -Seconds 2
    }
    Write-Progress -Id $WaitProgressId -ParentId $SetupProgressId -Activity "Waiting for Docker daemon" -Completed
    throw "Docker daemon did not become ready within 2 minutes. Open Docker Desktop and resolve any startup, license agreement, WSL 2, or virtualization error shown there, then re-run this script."
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
        Write-Host "Docker CLI was not found."
        Install-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
        Refresh-ToolPath
    }

    if (-not (Test-Command docker)) {
        throw "docker command not found after installing Docker Desktop. Restart PowerShell, then re-run this script."
    }

    Write-Host "Checking Docker Compose..."
    if ((Invoke-NativeQuiet -Command "docker" -Arguments @("compose", "version")) -ne 0) {
        throw "docker compose is not available. Check Docker Desktop installation."
    }
    Write-Host "Docker Compose is available."

    Write-Host "Checking Docker daemon (timeout: 5 seconds)..."
    if (-not (Test-DockerDaemon -TimeoutSeconds 5)) {
        Write-Host "Docker daemon is not responding."
        $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if ((Invoke-NativeQuiet -Command "docker" -Arguments @("desktop", "version")) -eq 0) {
            Write-Host "Starting Docker Desktop from the command line..."
            Invoke-RequiredNative `
                -Command "docker" `
                -Arguments @("desktop", "start") `
                -ErrorMessage "Docker Desktop CLI could not start Docker Desktop."
        }
        elseif (Test-Path $DockerDesktop) {
            Write-Host "Starting Docker Desktop..."
            Start-Process $DockerDesktop | Out-Null
        }
        else {
            throw "Docker Desktop executable was not found after installation."
        }
        Wait-DockerReady
    }
    else {
        Write-Host "Docker daemon is ready."
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

function Get-WslVerboseLines {
    return @(
        wsl --list --verbose |
            ForEach-Object { ($_ -replace "`0", "").TrimEnd() }
    )
}

function Get-DefaultWslDistro {
    $DefaultLine = Get-WslVerboseLines | Where-Object { $_ -match '^\s*\*' } | Select-Object -First 1
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

function Get-UserWslDistros {
    $Distros = @(
        wsl --list --quiet |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object {
                $_ -and
                $_ -notmatch '^docker-desktop($|-)' -and
                $_ -ne 'docker-desktop-data'
            }
    )

    return $Distros
}

function Select-ExistingWslDistro {
    $Distros = @(Get-UserWslDistros)
    if ($Distros.Count -eq 0) {
        return $null
    }

    $Ubuntu = $Distros | Where-Object { $_ -eq "Ubuntu" } | Select-Object -First 1
    if (-not $Ubuntu) {
        $Ubuntu = $Distros | Where-Object { $_ -like "Ubuntu*" } | Select-Object -First 1
    }

    if ($Ubuntu) {
        return $Ubuntu
    }

    return $Distros[0]
}

function Get-DefaultWslVersion {
    $DefaultLine = Get-WslVerboseLines | Where-Object { $_ -match '^\s*\*' } | Select-Object -First 1
    if ($DefaultLine -and $DefaultLine -match '\s+([12])\s*$') {
        return [int]$Matches[1]
    }

    return $null
}

function Ensure-WSL2 {
    if (-not (Test-Command wsl)) {
        if ($SkipInstall) {
            throw "WSL is not installed. Re-run without -SkipInstall to enable the required Windows features."
        }

        Write-Host "WSL is not installed. Requesting administrator permission to enable WSL 2 features..."
        $ElevatedCommands = @'
& dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
exit $LASTEXITCODE
'@
        $EncodedCommands = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ElevatedCommands))

        try {
            $InstallProcess = Start-Process `
                -FilePath "powershell.exe" `
                -Verb RunAs `
                -ArgumentList @("-NoProfile", "-EncodedCommand", $EncodedCommands) `
                -Wait `
                -PassThru
        }
        catch {
            throw "Administrator permission was not granted. WSL 2 installation requires an elevated PowerShell process."
        }

        if ($InstallProcess.ExitCode -ne 0) {
            throw "Could not enable the Windows features required by WSL 2. Verify that Windows is up to date and hardware virtualization is enabled."
        }

        throw "WSL 2 Windows features were enabled. Restart Windows, then run this script again to install the default Linux distribution."
    }

    $DefaultDistro = Get-DefaultWslDistro
    if (-not $DefaultDistro) {
        $ExistingDistro = Select-ExistingWslDistro
        if ($ExistingDistro) {
            Write-Host "No default WSL distribution is set. Reusing existing distribution '$ExistingDistro'..."
            Invoke-RequiredNative `
                -Command "wsl" `
                -Arguments @("--set-default", $ExistingDistro) `
                -ErrorMessage "Could not set '$ExistingDistro' as the default WSL distribution."
            $DefaultDistro = $ExistingDistro
        }
    }

    if (-not $DefaultDistro) {
        if ($SkipInstall) {
            throw "No default WSL distribution was found. Install a WSL 2 distribution, then retry."
        }

        Write-Host "No reusable WSL distribution was found. Installing Ubuntu..."
        try {
            $InstallProcess = Start-Process `
                -FilePath "wsl.exe" `
                -Verb RunAs `
                -ArgumentList @("--install", "--distribution", "Ubuntu", "--no-launch") `
                -Wait `
                -PassThru
        }
        catch {
            throw "Administrator permission was not granted. Installing WSL requires an elevated PowerShell process."
        }

        if ($InstallProcess.ExitCode -ne 0) {
            throw "WSL distribution installation failed. Check Windows Update and virtualization settings."
        }

        throw "Ubuntu installation was started. Reboot Windows if requested, launch Ubuntu once to complete its setup, then run this script again."
    }

    $WslVersion = Get-DefaultWslVersion
    if ($WslVersion -eq 2) {
        Write-Host "Default WSL distribution '$DefaultDistro' is using WSL 2."
        return
    }

    if ($WslVersion -ne 1) {
        throw "Could not determine the WSL version for '$DefaultDistro'. Run 'wsl --list --verbose' and verify its VERSION column."
    }

    if ($SkipInstall) {
        throw "Default WSL distribution '$DefaultDistro' is using WSL 1. Re-run without -SkipInstall to convert it to WSL 2."
    }

    Write-Host "Default WSL distribution '$DefaultDistro' is using WSL 1."
    Write-Host "Updating WSL before conversion..."
    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @("--update") `
        -ErrorMessage "WSL update failed. Run 'wsl --update' from an elevated PowerShell window."

    Write-Host "Setting WSL 2 as the default for new distributions..."
    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @("--set-default-version", "2") `
        -ErrorMessage "Could not set WSL 2 as the default. Enable the Virtual Machine Platform Windows feature and virtualization."

    Write-Host "Converting '$DefaultDistro' to WSL 2. This can take several minutes..."
    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @("--set-version", $DefaultDistro, "2") `
        -ErrorMessage "WSL 2 conversion failed. Back up the distribution and check available disk space and virtualization settings."

    if ((Get-DefaultWslVersion) -ne 2) {
        throw "WSL conversion completed without an error, but '$DefaultDistro' is not reported as WSL 2."
    }

    Write-Host "Converted '$DefaultDistro' to WSL 2."
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
            Write-Progress -Id $WaitProgressId -ParentId $SetupProgressId -Activity "Waiting for Docker Desktop WSL integration" -Completed
            Write-Host "Docker Desktop WSL integration is ready."
            return
        }
        Write-WaitProgress -Activity "Waiting for Docker Desktop WSL integration" -Attempt ($i + 1) -MaximumAttempts 60
        Start-Sleep -Seconds 2
    }

    Write-Progress -Id $WaitProgressId -ParentId $SetupProgressId -Activity "Waiting for Docker Desktop WSL integration" -Completed
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

try {
    Write-SetupProgress -Percent 0 -Status "Preparing directories"
    New-Item -ItemType Directory -Force -Path "workspace" | Out-Null
    New-Item -ItemType Directory -Force -Path "log" | Out-Null

    Write-SetupProgress -Percent 10 -Status "Checking WSL 2"
    Ensure-WSL2

    Write-SetupProgress -Percent 25 -Status "Checking Docker Desktop"
    Ensure-DockerDesktop

    if ($Mode -eq "VcXsrv") {
        Write-SetupProgress -Percent 40 -Status "Checking VcXsrv"
        Ensure-VcXsrv

        Write-SetupProgress -Percent 60 -Status "Configuring the VcXsrv environment"
        $env:DISPLAY = "host.docker.internal:0.0"
        $env:UID = "1000"
        $env:GID = "1000"

        if (-not $NoBuild) {
            Write-SetupProgress -Percent 70 -Status "Building Docker images (this may take several minutes)"
            Invoke-RequiredNative `
                -Command "docker" `
                -Arguments @("compose", "-f", "docker-compose.yml", "-f", "docker-compose.windows.yml", "build") `
                -ErrorMessage "Docker image build failed. Fix the build error above, then re-run this script."
        }
        else {
            Write-SetupProgress -Percent 90 -Status "Skipping Docker image build (-NoBuild)"
        }

        Write-SetupProgress -Percent 100 -Status "Setup completed"
        Write-Host "Windows VcXsrv setup completed."
        Write-Host "Run: .\run-windows.ps1"

        if ($Launch) {
            Write-Host "Launching run-windows.ps1..."
            .\run-windows.ps1
        }
    }
    else {
        Write-SetupProgress -Percent 40 -Status "Checking WSLg and Docker integration"
        Ensure-WSLg

        Write-SetupProgress -Percent 60 -Status "Resolving the repository path in WSL"
        $WslRepoPath = Get-WSLRepoPath

        if (-not $NoBuild) {
            Write-SetupProgress -Percent 70 -Status "Building Docker images in WSL (this may take several minutes)"
            Invoke-RequiredNative `
                -Command "wsl" `
                -Arguments @("--exec", "bash", "-lc", "cd '$WslRepoPath' && if docker compose version >/dev/null 2>&1; then docker compose -f docker-compose.yml -f docker-compose.wslg.yml build; elif docker-compose version >/dev/null 2>&1; then docker-compose -f docker-compose.yml -f docker-compose.wslg.yml build; else echo 'Docker Compose is not available inside WSL. Enable Docker Desktop WSL integration for this distro, or install the Docker Compose plugin in WSL.' >&2; exit 1; fi") `
                -ErrorMessage "WSLg Docker image build failed. Fix the build error above, then re-run this script."
        }
        else {
            Write-SetupProgress -Percent 90 -Status "Skipping Docker image build (-NoBuild)"
        }

        Write-SetupProgress -Percent 100 -Status "Setup completed"
        Write-Host "Windows WSLg setup checks completed."
        Write-Host "Open this repository inside WSL and run: ./run-wslg.sh"

        if ($Launch) {
            Write-Host "Launching run-wslg.sh..."
            wsl --exec sh -lc "cd '$WslRepoPath' && ./run-wslg.sh"
        }
    }
}
finally {
    Write-Progress -Id $WaitProgressId -ParentId $SetupProgressId -Activity "Waiting" -Completed
    Write-Progress -Id $SetupProgressId -Activity "Windows setup ($Mode)" -Completed
}
