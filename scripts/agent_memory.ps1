# flutter_agent_memory development wrapper for Windows
# Usage: .\scripts\agent_memory.ps1 [command] [args...]
# The CLI itself loads a .env file from the current directory when present.

$ErrorActionPreference = "Stop"

$RepoDir = Resolve-Path (Join-Path $PSScriptRoot "..")

# Find dart command
$DartCmd = $null
if (Get-Command dart -ErrorAction SilentlyContinue) {
    $DartCmd = "dart"
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
    $DartCmd = "flutter pub run"
} elseif (Test-Path "$env:USERPROFILE\.flutter_agent_memory\dart-sdk\bin\dart.exe") {
    $DartCmd = "$env:USERPROFILE\.flutter_agent_memory\dart-sdk\bin\dart.exe"
}

if (-not $DartCmd) {
    Write-Error "Dart SDK not found. Install it from https://dart.dev/get-dart or run scripts\install.ps1"
    exit 1
}

Set-Location $RepoDir

if ($DartCmd -eq "flutter pub run") {
    flutter run --target=bin/agent_memory.dart -- @args
} else {
    & $DartCmd run bin/agent_memory.dart -- @args
}
