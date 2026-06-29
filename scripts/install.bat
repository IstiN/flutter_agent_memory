@echo off
REM flutter_agent_memory CLI installer bootstrap for Windows
REM Usage: scripts\install.bat

powershell -ExecutionPolicy Bypass -Command "& {Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/scripts/install.ps1' -UseBasicParsing | Invoke-Expression}"
