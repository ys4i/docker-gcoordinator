param(
    [ValidateSet("VcXsrv", "WSLg")]
    [string]$Mode = "VcXsrv",
    [switch]$SkipInstall,
    [switch]$NoBuild,
    [switch]$Launch,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$SetupProgressId = 1
$ShouldLaunch = $Launch -or -not $NoLaunch

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
    Add-PathIfExists -Path (Join-Path $env:ProgramFiles "VcXsrv")
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

    return $null
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
    $ExistingDistro = Select-ExistingWslDistro
    if ($ExistingDistro -and $DefaultDistro -ne $ExistingDistro) {
        Write-Host "Setting existing Ubuntu distribution '$ExistingDistro' as the default..."
        Invoke-RequiredNative `
            -Command "wsl" `
            -Arguments @("--set-default", $ExistingDistro) `
            -ErrorMessage "Could not set '$ExistingDistro' as the default WSL distribution."
        $DefaultDistro = $ExistingDistro
    }
    elseif (-not $ExistingDistro) {
        $DefaultDistro = $null
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

function Get-OrCreateWSLUser {
    param(
        [string]$Distro,
        [string]$WslRepoPath
    )

    $ExistingUser = [string](
        wsl --distribution $Distro --user root --exec sh -lc `
            "getent passwd | awk -F: '`$3 >= 1000 && `$3 < 65534 && `$1 ~ /^[a-z_][a-z0-9_-]*`$/ { print `$1; exit }'"
    )
    $ExistingUser = $ExistingUser.Trim()

    if ($ExistingUser) {
        $WslUser = $ExistingUser
        Write-Host "Using existing WSL user '$WslUser'."
    }
    else {
        $WindowsUserName = [string]$env:USERNAME
        $WslUser = $WindowsUserName.ToLowerInvariant() -replace '[^a-z0-9_-]', ''
        if (-not $WslUser -or $WslUser -notmatch '^[a-z_]') {
            $WslUser = "gcoordinator"
        }
        Write-Host "No regular WSL user was found. Creating '$WslUser'..."
    }

    if ($SkipInstall) {
        $CurrentUid = [string](
            wsl --distribution $Distro --exec id -u
        )
        $CurrentUid = $CurrentUid.Trim()
        if ($CurrentUid -eq "0") {
            throw "The default WSL user is root. Re-run without -SkipInstall to create and configure a regular user."
        }
        return $WslUser
    }

    Invoke-RequiredNative `
        -Command "wsl" `
        -Arguments @(
            "--distribution", $Distro,
            "--user", "root",
            "--exec", "bash", "-lc",
            "cd '$WslRepoPath' && sed -i 's/\r$//' setup-wsl-user.sh && bash ./setup-wsl-user.sh prepare '$WslUser'"
        ) `
        -ErrorMessage "Could not create or configure the regular WSL user '$WslUser'."

    return $WslUser
}

function Restart-WSLDistroForDefaultUser {
    param([string]$Distro)

    if (-not $SkipInstall) {
        Write-Host "Restarting WSL distribution to activate the default user..."
        Invoke-RequiredNative `
            -Command "wsl" `
            -Arguments @("--terminate", $Distro) `
            -ErrorMessage "Could not restart WSL distribution '$Distro'. Run 'wsl --shutdown', then retry."
    }
}

function Ensure-WSLDockerEngine {
    param(
        [string]$Distro,
        [string]$WslUser,
        [string]$WslRepoPath
    )

    if ($SkipInstall) {
        Write-Host "Checking Docker Engine inside WSL Ubuntu..."
        Invoke-RequiredNative `
            -Command "wsl" `
            -Arguments @("--distribution", $Distro, "--user", $WslUser, "--exec", "bash", "-lc", "docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1") `
            -ErrorMessage "Docker Engine or Docker Compose is not ready inside WSL. Re-run without -SkipInstall to install it."
        return
    }

    Write-Host "Installing or checking Docker Engine inside WSL Ubuntu..."
    wsl --distribution $Distro --user $WslUser --exec bash -lc `
        "cd '$WslRepoPath' && sed -i 's/\r$//' setup-wsl-docker.sh && chmod +x setup-wsl-docker.sh && ./setup-wsl-docker.sh"
    $DockerSetupExitCode = $LASTEXITCODE

    wsl --distribution $Distro --user root --exec bash -lc `
        "cd '$WslRepoPath' && bash ./setup-wsl-user.sh cleanup '$WslUser'"
    if ($LASTEXITCODE -ne 0) {
        throw "Docker setup permission cleanup failed inside WSL."
    }
    if ($DockerSetupExitCode -ne 0) {
        throw "Docker Engine setup inside WSL failed. Review the error above, then re-run this script."
    }
}

try {
    Write-SetupProgress -Percent 0 -Status "Preparing directories"
    New-Item -ItemType Directory -Force -Path "workspace" | Out-Null
    New-Item -ItemType Directory -Force -Path "log" | Out-Null

    Write-SetupProgress -Percent 10 -Status "Checking WSL 2"
    Ensure-WSL2

    Write-SetupProgress -Percent 20 -Status "Resolving the repository path in WSL"
    $WslRepoPath = Get-WSLRepoPath
    $WslDistro = Get-DefaultWslDistro

    Write-SetupProgress -Percent 25 -Status "Configuring a regular WSL user"
    $WslUser = Get-OrCreateWSLUser -Distro $WslDistro -WslRepoPath $WslRepoPath

    Write-SetupProgress -Percent 30 -Status "Installing Docker Engine in WSL Ubuntu"
    Ensure-WSLDockerEngine -Distro $WslDistro -WslUser $WslUser -WslRepoPath $WslRepoPath

    if ($Mode -eq "VcXsrv") {
        Write-SetupProgress -Percent 40 -Status "Checking VcXsrv"
        Ensure-VcXsrv

        Write-SetupProgress -Percent 60 -Status "Configuring the VcXsrv environment"

        if (-not $NoBuild) {
            Write-SetupProgress -Percent 70 -Status "Building Docker images in WSL (this may take several minutes)"
            Invoke-RequiredNative `
                -Command "wsl" `
                -Arguments @("--distribution", $WslDistro, "--user", $WslUser, "--exec", "bash", "-lc", "cd '$WslRepoPath' && docker compose -f docker-compose.yml -f docker-compose.windows.yml build") `
                -ErrorMessage "Docker image build failed. Fix the build error above, then re-run this script."
        }
        else {
            Write-SetupProgress -Percent 90 -Status "Skipping Docker image build (-NoBuild)"
        }

        Restart-WSLDistroForDefaultUser -Distro $WslDistro
        Write-SetupProgress -Percent 100 -Status "Setup completed"
        Write-Host "Windows VcXsrv setup completed."
        Write-Host "Run: .\run-windows.ps1"

        if ($ShouldLaunch) {
            Write-Host "Launching run-windows.ps1..."
            .\run-windows.ps1 -Mode VcXsrv
        }
    }
    else {
        Write-SetupProgress -Percent 40 -Status "Checking WSLg"
        Ensure-WSLg

        Write-SetupProgress -Percent 60 -Status "Preparing the WSLg build"

        if (-not $NoBuild) {
            Write-SetupProgress -Percent 70 -Status "Building Docker images in WSL (this may take several minutes)"
            Invoke-RequiredNative `
                -Command "wsl" `
                -Arguments @("--distribution", $WslDistro, "--user", $WslUser, "--exec", "bash", "-lc", "cd '$WslRepoPath' && docker compose -f docker-compose.yml -f docker-compose.wslg.yml build") `
                -ErrorMessage "WSLg Docker image build failed. Fix the build error above, then re-run this script."
        }
        else {
            Write-SetupProgress -Percent 90 -Status "Skipping Docker image build (-NoBuild)"
        }

        Restart-WSLDistroForDefaultUser -Distro $WslDistro
        Write-SetupProgress -Percent 100 -Status "Setup completed"
        Write-Host "Windows WSLg setup checks completed."
        Write-Host "Open this repository inside WSL and run: ./run-wslg.sh"

        if ($ShouldLaunch) {
            Write-Host "Launching run-wslg.sh..."
            wsl --exec sh -lc "cd '$WslRepoPath' && ./run-wslg.sh"
        }
    }
}
finally {
    Write-Progress -Id $SetupProgressId -Activity "Windows setup ($Mode)" -Completed
}
