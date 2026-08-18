#Requires -Version 7.3
<#
.SYNOPSIS
    A Powershell script to setup a Koning Kevin Org computer.

.DESCRIPTION
    Sets up the following:
    - Google GCP: Making sure the user can log in with his Google account
    - Enable Windows Remote Management
    - Add kk-localadmin to SpecialAccounts\Userlist
    - Install Google Chrome
    - Install Google Drive for desktop
.EXAMPLE
    .\Setup.ps1

    Runs all setup tasks.
.EXAMPLE
    .\Setup.ps1 -Chrome

    Installs only Google Chrome.
.EXAMPLE
    .\Setup.ps1 -GCP -WinRm

    Installs Google Credential Provider and enables Windows Remote Management.
.EXAMPLE
    .\Setup.ps1 -Help

    Shows all available parameters and usage.
#>

param(
    [switch]$GCP,
    [switch]$WinRm,
    [switch]$LocalAdmin,
    [switch]$Chrome,
    [switch]$Drive,
    [switch]$Help
)

function Show-Help {
    Write-Output "Usage: Setup.ps1 [parameters]"
    Write-Output ""
    Write-Output "By default, runs all setup tasks."
    Write-Output ""
    Write-Output "Parameters:"
    Write-Output "  -GCP        Install and configure Google Credential Provider for Windows"
    Write-Output "  -WinRm      Enable Windows Remote Management"
    Write-Output "  -LocalAdmin Add kk-localadmin to SpecialAccounts\Userlist"
    Write-Output "  -Chrome     Install Google Chrome"
    Write-Output "  -Drive      Install Google Drive for desktop"
    Write-Output "  -Help       Show this help message"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  .\Setup.ps1                Run all setup tasks"
    Write-Output "  .\Setup.ps1 -Chrome        Install only Chrome"
    Write-Output "  .\Setup.ps1 -GCP -WinRm    Install GCP and enable WinRM"
}
function Assert-IsAdmin() {
    $admin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match 'S-1-5-32-544')
    <# Check if the current user is an admin and exit if they aren't. #>
    if (-not ($admin)) {
        Write-Output 'Please run as administrator!'
        exit 5
    }
    
}

function Install-GCP() {
    <# This script downloads Google Credential Provider for Windows from
    https://tools.google.com/dlpage/gcpw/, then installs and configures it.
    Windows administrator access is required to use the script. #>

    <# Set the following key to the domains you want to allow users to sign in from.

    For example:
    $domainsAllowedToLogin = "solarmora.com,altostrat.com"
    #>

    Assert-IsAdmin

    $domainsAllowedToLogin = "koningkevin.be"

    <# Choose the GCPW file to download. 32-bit and 64-bit versions have different names #>
    $gcpwFileName = 'gcpwstandaloneenterprise.msi'
    if ([Environment]::Is64BitOperatingSystem) {
        $gcpwFileName = 'gcpwstandaloneenterprise64.msi'
    }

    <# Download the GCPW installer. #>
    $gcpwUrlPrefix = 'https://dl.google.com/credentialprovider/'
    $gcpwUri = $gcpwUrlPrefix + $gcpwFileName
    Write-Host 'Downloading GCPW from' $gcpwUri
    Invoke-WebRequest -Uri $gcpwUri -OutFile $gcpwFileName

    <# Run the GCPW installer and wait for the installation to finish #>
    $arguments = "/i `"$gcpwFileName`""
    $installProcess = (Start-Process msiexec.exe -ArgumentList $arguments -PassThru -Wait)

    <# Check if installation was successful #>
    if ($installProcess.ExitCode -ne 0) {
        Write-Output 'Installation failed! Could not install Credential Provider'
        exit $installProcess.ExitCode
    }
    else {
        Write-Output 'Installation Succeeded: installed GCP'
    }

    <# Set the required registry key with the allowed domains #>
    $registryPath = 'HKEY_LOCAL_MACHINE\Software\Google\GCPW'
    $name = 'domains_allowed_to_login'
    [microsoft.win32.registry]::SetValue($registryPath, $name, $domainsAllowedToLogin)

    $domains = Get-ItemPropertyValue HKLM:\Software\Google\GCPW -Name $name

    if ($domains -eq $domainsAllowedToLogin) {
        Write-Output 'Configuration completed successfully!'
    }
    else {
        Write-Output 'Could not write to registry. Configuration was not completed.'

    }
}

function Enable-WinRm {
    Assert-IsAdmin

    winrm quickconfig -q
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
    winrm set winrm/config '@{MaxTimeoutms="1800000"}'
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    Start-Service WinRM
    set-service WinRM -StartupType Automatic

    Write-Output "WinRm Enabled"
}

function Add-LocalAdminToSpecialAccounts() {
    Assert-IsAdmin

    $registryPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\Userlist'
    $userName = 'kk-localadmin'

    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    New-ItemProperty -Path $registryPath -Name $userName -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Output "Added $userName to SpecialAccounts\Userlist"
}

function Install-Chrome() {
    Assert-IsAdmin

    $chromeFileName = 'GoogleChromeStandaloneEnterprise.msi'
    if ([Environment]::Is64BitOperatingSystem) {
        $chromeFileName = 'GoogleChromeStandaloneEnterprise64.msi'
    }

    $chromeUrlPrefix = 'https://dl.google.com/chrome/install/'
    $chromeUri = $chromeUrlPrefix + $chromeFileName
    Write-Host 'Downloading Chrome from' $chromeUri
    Invoke-WebRequest -Uri $chromeUri -OutFile $chromeFileName

    $arguments = "/i `"$chromeFileName`" /qn /norestart"
    $installProcess = Start-Process msiexec.exe -ArgumentList $arguments -PassThru -Wait

    if ($installProcess.ExitCode -ne 0) {
        Write-Output 'Chrome installation failed!'
        Remove-Item $chromeFileName -Force -ErrorAction SilentlyContinue
        exit $installProcess.ExitCode
    }
    else {
        Write-Output 'Chrome installed successfully'
        Remove-Item $chromeFileName -Force -ErrorAction SilentlyContinue
    }
}

function Install-GoogleDrive() {
    Assert-IsAdmin

    $driveFileName = 'GoogleDriveSetup.exe'
    $driveUri = 'https://dl.google.com/drive-file-stream/GoogleDriveSetup.exe'
    Write-Host 'Downloading Google Drive from' $driveUri
    Invoke-WebRequest -Uri $driveUri -OutFile $driveFileName

    $arguments = "--silent --skip_launch_new"
    $installProcess = Start-Process -FilePath $driveFileName -ArgumentList $arguments -PassThru -Wait

    if ($installProcess.ExitCode -ne 0) {
        Write-Output 'Google Drive installation failed!'
        Remove-Item $driveFileName -Force -ErrorAction SilentlyContinue
        exit $installProcess.ExitCode
    }
    else {
        Write-Output 'Google Drive installed successfully'
        Remove-Item $driveFileName -Force -ErrorAction SilentlyContinue
    }
}

if ($Help) {
    Show-Help
    exit 0
}

$runAll = -not ($GCP -or $WinRm -or $LocalAdmin -or $Chrome -or $Drive)

if ($runAll -or $GCP) { Install-GCP }
if ($runAll -or $WinRm) { Enable-WinRm }
if ($runAll -or $LocalAdmin) { Add-LocalAdminToSpecialAccounts }
if ($runAll -or $Chrome) { Install-Chrome }
if ($runAll -or $Drive) { Install-GoogleDrive }