# flutter_agent_memory CLI installer for Windows
# Usage:
#   irm https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/scripts/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo = "IstiN/flutter_agent_memory"
$InstallDir = if ($env:FAM_INSTALL_DIR) { $env:FAM_INSTALL_DIR } else { "$env:USERPROFILE\.flutter_agent_memory" }
$BinDir = "$InstallDir\bin"
$DartSdkDir = "$InstallDir\dart-sdk"
$RepoDir = "$InstallDir\repo"
$BinaryPath = "$BinDir\agent_memory.exe"
$WrapperPath = "$BinDir\agent_memory.bat"

$DartVersion = if ($env:FAM_DART_VERSION) { $env:FAM_DART_VERSION } else { "3.10.8" }

$Arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { "arm64" }
    default { "x64" }
}
$Os = "windows"

function Ensure-Dart {
    $dart = Get-Command dart -ErrorAction SilentlyContinue
    if ($dart) {
        Write-Host "Using system Dart: $(& dart --version 2>&1 | Select-Object -First 1)" -ForegroundColor Green
        return $dart.Source
    }

    $bundled = "$DartSdkDir\bin\dart.exe"
    if (Test-Path $bundled) {
        Write-Host "Using bundled Dart from $DartSdkDir" -ForegroundColor Green
        $env:PATH = "$DartSdkDir\bin;$env:PATH"
        return $bundled
    }

    Write-Host "Dart not found. Downloading Dart SDK $DartVersion for $Os-$Arch..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $DartSdkDir | Out-Null

    $archive = "dartsdk-$Os-$Arch-release.zip"
    $url = "https://storage.googleapis.com/dart-archive/channels/stable/release/$DartVersion/sdk/$archive"
    $tmpArchive = "$InstallDir\$archive"

    Invoke-WebRequest -Uri $url -OutFile $tmpArchive -UseBasicParsing
    Expand-Archive -Path $tmpArchive -DestinationPath $InstallDir -Force
    Remove-Item $tmpArchive -Force

    $env:PATH = "$DartSdkDir\bin;$env:PATH"
    return "$DartSdkDir\bin\dart.exe"
}

function Install-Repo {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    if ($env:FAM_REPO_DIR) {
        Write-Host "Using local repository from $($env:FAM_REPO_DIR)..." -ForegroundColor Cyan
        Remove-Item -Recurse -Force $RepoDir -ErrorAction SilentlyContinue
        Copy-Item -Recurse -Force $env:FAM_REPO_DIR $RepoDir
        return
    }

    if (Test-Path "$RepoDir\.git") {
        Write-Host "Updating existing repository..." -ForegroundColor Cyan
        Push-Location $RepoDir
        git pull --rebase
        Pop-Location
    } else {
        Write-Host "Cloning $Repo..." -ForegroundColor Cyan
        Remove-Item -Recurse -Force $RepoDir -ErrorAction SilentlyContinue
        git clone --depth 1 "https://github.com/$Repo.git" $RepoDir
    }
}

function Compile-Binary {
    param($DartCmd)

    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    Push-Location $RepoDir
    & $DartCmd pub get
    Pop-Location

    Write-Host "Compiling native binary..." -ForegroundColor Cyan
    & $DartCmd compile exe "$RepoDir\bin\agent_memory.dart" -o $BinaryPath

    Write-Host "Binary compiled: $BinaryPath" -ForegroundColor Green
}

function Create-Wrapper {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

    $wrapper = @"
@echo off
REM flutter_agent_memory wrapper
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_DIR=%SCRIPT_DIR%.."
for %%F in ("%INSTALL_DIR%") do set "INSTALL_DIR=%%~fF"
set "DART_SDK_DIR=$DartSdkDir"
set "BINARY=$BinaryPath"

if exist "%DART_SDK_DIR%\bin\dart.exe" (
    set "PATH=%DART_SDK_DIR%\bin;%PATH%"
)

if exist "%BINARY%" (
    "%BINARY%" %*
) else (
    echo Error: agent_memory binary not found at %BINARY%
    exit /b 1
)
"@

    Set-Content -Path $WrapperPath -Value $wrapper
    Write-Host "Wrapper installed: $WrapperPath" -ForegroundColor Green
}

function Update-Path {
    $pathEntry = $BinDir
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$pathEntry*") {
        [Environment]::SetEnvironmentVariable("PATH", "$pathEntry;$currentPath", "User")
        Write-Host "Added $BinDir to user PATH" -ForegroundColor Green
        Write-Host "Restart your terminal to use 'agent_memory'" -ForegroundColor Yellow
    }
}

function Main {
    Write-Host "Installing flutter_agent_memory CLI..." -ForegroundColor Green
    $dartCmd = Ensure-Dart
    Install-Repo
    Compile-Binary -DartCmd $dartCmd
    Create-Wrapper
    Update-Path
    Write-Host "Installation complete." -ForegroundColor Green
    Write-Host "Usage: $WrapperPath --help" -ForegroundColor Green
}

Main
