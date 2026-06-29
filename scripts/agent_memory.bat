@echo off
REM flutter_agent_memory development wrapper for Windows
REM Usage: scripts\agent_memory.bat [command] [args...]
REM The CLI itself loads a .env file from the current directory when present.

setlocal

set "REPO_DIR=%~dp0.."
for %%F in ("%REPO_DIR%") do set "REPO_DIR=%%~fF"

REM Find dart command
set "DART_CMD="
where dart >nul 2>nul && set "DART_CMD=dart"
if not defined DART_CMD where flutter >nul 2>nul && set "DART_CMD=flutter pub run"
if not defined DART_CMD (
  if exist "%USERPROFILE%\.flutter_agent_memory\dart-sdk\bin\dart.exe" (
    set "DART_CMD=%USERPROFILE%\.flutter_agent_memory\dart-sdk\bin\dart.exe"
  )
)

if not defined DART_CMD (
  echo Error: Dart SDK not found.
  echo Install it from https://dart.dev/get-dart or run scripts\install.bat
  exit /b 1
)

cd /d "%REPO_DIR%"

if "%DART_CMD%"=="flutter pub run" (
  flutter run --target=bin\agent_memory.dart -- %*
) else (
  "%DART_CMD%" run bin\agent_memory.dart -- %*
)
