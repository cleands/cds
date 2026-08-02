@echo off
chcp 65001 >nul
setlocal
set "PS_FILE=%TEMP%\CleanerDS.ps1"

powershell -NoProfile -ExecutionPolicy Bypass ^
  -Command "try { Invoke-WebRequest 'https://cleands.github.io/cds/script.ps1' -OutFile '%PS_FILE%' -UseBasicParsing } catch { exit 1 }"

if not exist "%PS_FILE%" (
    echo Failed to download CleanerDS.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

del /f /q "%PS_FILE%" >nul 2>&1
exit
