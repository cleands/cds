<# :
@echo off
REM Меняем кодировку на UTF-8 для нормального отображения русского языка
chcp 65001 > nul

REM Запускаем этот же файл, но заставляем PowerShell прочитать его как свой скрипт
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression -Command (Get-Content -Raw '%~f0')"

REM Закрываем батник, чтобы он не пошел читать код дальше и не выдал ошибки
exit /b
#>

# ==============================================================================
# НАЧАЛО POWERSHELL СКРИПТА (CleanerDS)
# ==============================================================================

# Загрузка сборок Windows Forms и Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Скрываем черное окно консоли, оставляя только интерфейс
$AsyncScript = {
    $code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32Utils" -PassThru
    $hwnd = (Get-Process -Id $PID).MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { $type::ShowWindow($hwnd, 0) }
}
try { &$AsyncScript } catch { }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Защита от двойного запуска (чтобы нельзя было открыть 10 окон сразу)
$script:AppMutexName = "Global\CleanerDS_SingleInstance_Mutex"
$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, $script:AppMutexName, [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show("Приложение CleanerDS уже запущено!", "Предупреждение", 0, 48)
    exit
}

# Пути к файлам и директориям
$script:LocalAppData = [Environment]::GetFolderPath("LocalApplicationData")
$script:AppData = [Environment]::GetFolderPath("ApplicationData")
$script:DiscordPath = Join-Path -Path $script:LocalAppData -ChildPath "Discord"
$script:CachePath = Join-Path -Path $script:AppData -ChildPath "discord\Cache"
$script:BackupPath = Join-Path -Path $script:DiscordPath -ChildPath "backup"

# Список исключений (что мы НЕ удаляем)
$script:KeepLocales = @("ru.pak", "en-US.pak")
$script:KeepModules = @("discord_desktop_core*", "discord_krisp*", "discord_modules*", "discord_utils*", "discord_voice*")

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    if ($null -ne $script:RichTextBoxLog) {
        $script:RichTextBoxLog.SelectionStart = $script:RichTextBoxLog.TextLength
        $script:RichTextBoxLog.SelectionLength = 0
        $color = switch ($Level) {
            "SUCCESS" { [System.Drawing.Color]::ForestGreen }
            "WARN"    { [System.Drawing.Color]::Gold }
            "ERROR"   { [System.Drawing.Color]::Crimson }
            Default   { [System.Drawing.Color]::Gainsboro }
        }
        $script:RichTextBoxLog.SelectionColor = $color
        $script:RichTextBoxLog.AppendText("[$timestamp] $Message`r`n")
        $script:RichTextBoxLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Update-ProgressBar([int]$Value) {
    if ($null -ne $script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Find-Discord {
    if (-not (Test-Path -Path $script:DiscordPath)) { return $null }
    $latestApp = Get-ChildItem -Path $script:DiscordPath -Directory -Filter "app-*" | 
                 Sort-Object { try { [version]($_.Name -replace 'app-', '') } catch { [version]"0.0.0" } } -Descending | 
                 Select-Object -First 1
    if ($latestApp) { return $latestApp.FullName }
    return $null
}

function Stop-Discord {
    $processes = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Log "Завершение процессов Discord..." "WARN"
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    return $true
}

function Start-Discord {
    $appFolder = Find-Discord
    if ($appFolder) {
        $exePath = Join-Path -Path $appFolder -ChildPath "Discord.exe"
        if (Test-Path -Path $exePath) {
            Start-Process -FilePath $exePath
            Write-Log "Discord запущен." "SUCCESS"
        }
    }
    Update-Status
}

function Create-Backup([bool]$ShowDialogs = $true) {
    Update-ProgressBar 10
    $appFolder = Find-Discord
    if (-not $appFolder) { return $false }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $targetFolder = Join-Path -Path $script:BackupPath -ChildPath $timestamp
    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    Write-Log "Создание резервной копии: $timestamp" "INFO"

    $modulesSrc = Join-Path -Path $appFolder -ChildPath "modules"
    if (Test-Path -Path $modulesSrc) { Copy-Item -Path $modulesSrc -Destination "$targetFolder\modules" -Recurse -Force }
    
    $localesSrc = Join-Path -Path $appFolder -ChildPath "locales"
    if (Test-Path -Path $localesSrc) { Copy-Item -Path $localesSrc -Destination "$targetFolder\locales" -Recurse -Force }

    Update-ProgressBar 100
    Write-Log "Резервная копия успешно создана." "SUCCESS"
    if ($ShowDialogs) { [System.Windows.Forms.MessageBox]::Show("Резервная копия создана успешно!", "Успех", 0, 64) }
    Update-Status; Update-ProgressBar 0
    return $true
}

function Start-CleaningProcess {
    if (-not $script:ChkLoc.Checked -and -not $script:ChkMod.Checked -and -not $script:ChkCac.Checked) {
        [System.Windows.Forms.MessageBox]::Show("Выберите хотя бы один пункт для очистки!", "Внимание", 0, 48)
        return
    }

    $hasBackup = (Test-Path -Path $script:BackupPath) -and ((Get-ChildItem -Path $script:BackupPath -Directory).Count -gt 0)
    if (-not $hasBackup) {
        if ([System.Windows.Forms.MessageBox]::Show("Резервная копия отсутствует.`nСоздать её сейчас?", "Запрос", 4, 32) -eq "Yes") {
            if (-not (Create-Backup $false)) { return }
        } else { return }
    }

    Update-ProgressBar 10; Stop-Discord | Out-Null
    $appFolder = Find-Discord

    if ($script:ChkLoc.Checked -and $appFolder) {
        $locDir = Join-Path -Path $appFolder -ChildPath "locales"
        if (Test-Path -Path $locDir) {
            Write-Log "Очистка лишних языков..." "INFO"
            Get-ChildItem -Path $locDir -File | Where-Object { $script:KeepLocales -notcontains $_.Name } | Remove-Item -Force
        }
    }

    Update-ProgressBar 50
    if ($script:ChkMod.Checked -and $appFolder) {
        $modDir = Join-Path -Path $appFolder -ChildPath "modules"
        if (Test-Path -Path $modDir) {
            Write-Log "Очистка мусорных модулей..." "INFO"
            Get-ChildItem -Path $modDir -Directory | ForEach-Object {
                $mod = $_; $keep = $false
                foreach ($pat in $script:KeepModules) { if ($mod.Name -like $pat) { $keep = $true; break } }
                if (-not $keep) { Remove-Item -Path $mod.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Update-ProgressBar 80
    if ($script:ChkCac.Checked -and (Test-Path -Path $script:CachePath)) {
        Write-Log "Очистка кэша Discord..." "INFO"
        Get-ChildItem -Path $script:CachePath -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Update-ProgressBar 100
    Write-Log "Очистка Discord полностью завершена!" "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Discord успешно очищен!", "Успех", 0, 64)
    Update-Status; Update-ProgressBar 0
}

function Show-BackupSelectionDialog([string]$Title, [string]$BtnText) {
    if (-not (Test-Path -Path $script:BackupPath)) { return $null }
    $backups = Get-ChildItem -Path $script:BackupPath -Directory | Sort-Object Name -Descending
    if ($backups.Count -eq 0) { return $null }

    $dlg = New-Object System.Windows.Forms.Form -Property @{ Text = $Title; Size = New-Object System.Drawing.Size(400, 320); StartPosition = "CenterParent"; BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54); ForeColor = [System.Drawing.Color]::White; FormBorderStyle = "FixedDialog" }
    $list = New-Object System.Windows.Forms.ListBox -Property @{ Location = New-Object System.Drawing.Point(20, 20); Size = New-Object System.Drawing.Size(345, 180); BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37); ForeColor = "White" }
    foreach ($b in $backups) { [void]$list.Items.Add($b.Name) }
    $list.SelectedIndex = 0

    $btnOk = New-Object System.Windows.Forms.Button -Property @{ Text = $BtnText; Location = New-Object System.Drawing.Point(165, 220); Size = New-Object System.Drawing.Size(100, 35); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); DialogResult = "OK"; FlatStyle = "Flat" }
    $dlg.Controls.AddRange(@($list, $btnOk))
    if ($dlg.ShowDialog() -eq "OK") { return $list.SelectedItem.ToString() }
    return $null
}

function Restore-Backup {
    $sel = Show-BackupSelectionDialog "Восстановление бэкапа" "Восстановить"
    if (-not $sel) { return }
    Stop-Discord | Out-Null
    $appFolder = Find-Discord
    $bDir = Join-Path -Path $script:BackupPath -ChildPath $sel
    
    if (Test-Path "$bDir\modules") { Copy-Item "$bDir\modules\*" "$appFolder\modules" -Recurse -Force }
    if (Test-Path "$bDir\locales") { Copy-Item "$bDir\locales\*" "$appFolder\locales" -Recurse -Force }
    
    Write-Log "Восстановление завершено." "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Данные успешно восстановлены!", "Успех", 0, 64)
}

function Delete-Backup {
    $sel = Show-BackupSelectionDialog "Удаление бэкапа" "Удалить"
    if ($sel -and ([System.Windows.Forms.MessageBox]::Show("Удалить бэкап $sel?", "Подтверждение", 4, 48) -eq "Yes")) {
        Remove-Item (Join-Path $script:BackupPath $sel) -Recurse -Force
        Write-Log "Удален бэкап: $sel" "SUCCESS"
        Update-Status
    }
}

function Show-Help([string]$Title, [string]$Text) {
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, 0, 64)
}

function Update-Status {
    $script:LblStatusDiscord.Text = if (Get-Process "Discord" -ea 0) { "Запущен" } else { "Остановлен" }
    $script:LblStatusDiscord.ForeColor = if (Get-Process "Discord" -ea 0) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Gray }
    $app = Find-Discord
    $script:LblVersion.Text = if ($app) { (Split-Path $app -Leaf) -replace "app-", "" } else { "Не найден" }
    
    if (Test-Path $script:BackupPath) {
        $c = (Get-ChildItem $script:BackupPath -Directory).Count
        $script:LblStatusBackup.Text = "Доступно ($c)"
        $script:LblStatusBackup.ForeColor = if ($c -gt 0) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Crimson }
    }
}

# ------------------------------------------------------------------------------
# ГРАФИЧЕСКИЙ ИНТЕРФЕЙС
# ------------------------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form -Property @{ Text = "CleanerDS"; Size = New-Object System.Drawing.Size(900, 680); StartPosition = "CenterScreen"; FormBorderStyle = "FixedSingle"; BackColor = [System.Drawing.Color]::FromArgb(54, 57, 63); ForeColor = [System.Drawing.Color]::White }

$pHeader = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 70); Dock = "Top"; BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37) }
$pHeader.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "CleanerDS"; Font = New-Object System.Drawing.Font("Segoe UI", 20, 1); ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242); Location = New-Object System.Drawing.Point(20, 15); AutoSize = $true }))

$pStatus = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 45); Location = New-Object System.Drawing.Point(0, 70); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:LblStatusDiscord = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(125, 14); AutoSize = $true }
$script:LblStatusBackup = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(365, 14); AutoSize = $true }
$script:LblVersion = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(630, 14); AutoSize = $true }
$pStatus.Controls.AddRange(@(
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Статус Discord:"; Location = New-Object System.Drawing.Point(20, 14); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9, 1) }), $script:LblStatusDiscord,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Статус Backup:"; Location = New-Object System.Drawing.Point(260, 14); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9, 1) }), $script:LblStatusBackup,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Версия Discord:"; Location = New-Object System.Drawing.Point(520, 14); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9, 1) }), $script:LblVersion
))

$pOptions = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(20, 125); Size = New-Object System.Drawing.Size(620, 110); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:ChkLoc = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Удалить неиспользуемые языки (locales)"; Location = New-Object System.Drawing.Point(15, 12); Size = New-Object System.Drawing.Size(350, 25); Checked = $true }
$script:ChkMod = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Вырезать ненужные модули (modules)"; Location = New-Object System.Drawing.Point(15, 42); Size = New-Object System.Drawing.Size(350, 25); Checked = $true }
$script:ChkCac = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Очистить кэш, CodeCache и Temp"; Location = New-Object System.Drawing.Point(15, 72); Size = New-Object System.Drawing.Size(380, 25); Checked = $true }

function Make-HelpBtn([int]$y, [string]$t, [string]$m) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = "Зачем?"; Location = New-Object System.Drawing.Point(510, $y); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = "Hand" }
    $b.FlatAppearance.BorderSize = 0; $b.Add_Click({ Show-Help $t $m }); return $b
}
$pOptions.Controls.AddRange(@($script:ChkLoc, (Make-HelpBtn 10 "Языки" "Удаляет более 70 лишних языковых пакетов, оставляя только RU и EN. Это ускоряет старт."), 
                              $script:ChkMod, (Make-HelpBtn 40 "Модули" "Удаляет мусорные модули телеметрии и игр, оставляя звук и Krisp."),
                              $script:ChkCac, (Make-HelpBtn 70 "Кэш" "Чистит папку Cache, GPUCache и CodeCache, освобождая сотни мегабайт.")))

$script:RichTextBoxLog = New-Object System.Windows.Forms.RichTextBox -Property @{ Location = New-Object System.Drawing.Point(20, 245); Size = New-Object System.Drawing.Size(620, 355); BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37); ForeColor = [System.Drawing.Color]::Gainsboro; Font = New-Object System.Drawing.Font("Consolas", 9.5); ReadOnly = $true; BorderStyle = "None" }

$panelButtons = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(660, 125); Size = New-Object System.Drawing.Size(200, 475) }
function Make-Btn([string]$text, [int]$y, $action, $color = [System.Drawing.Color]::FromArgb(79, 84, 92)) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = $text; Location = New-Object System.Drawing.Point(0, $y); Size = New-Object System.Drawing.Size(200, 40); BackColor = $color; ForeColor = "White"; FlatStyle = "Flat"; Cursor = "Hand"; Font = New-Object System.Drawing.Font("Segoe UI", 9.5, 1) }
    $b.FlatAppearance.BorderSize = 0; $b.Add_Click($action); return $b
}
$panelButtons.Controls.AddRange(@(
    (Make-Btn "Создать Backup" 0 { Create-Backup }),
    (Make-Btn "Очистить Discord" 50 { Start-CleaningProcess } ([System.Drawing.Color]::FromArgb(237, 66, 69))),
    (Make-Btn "Восстановить" 100 { Restore-Backup } ([System.Drawing.Color]::FromArgb(88, 101, 242))),
    (Make-Btn "Удалить Backup" 150 { Delete-Backup }),
    (Make-Btn "Запустить Discord" 250 { Start-Discord } ([System.Drawing.Color]::FromArgb(57, 105, 54))),
    (Make-Btn "Выход" 435 { $form.Close() })
))

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = New-Object System.Drawing.Point(0, 615); Size = New-Object System.Drawing.Size(900, 10); Dock = "Bottom" }

$form.Controls.AddRange(@($pHeader, $pStatus, $pOptions, $script:RichTextBoxLog, $panelButtons, $script:ProgressBar))
$form.Add_Shown({ Write-Log "Интерфейс загружен." "SUCCESS"; Update-Status })
$form.Add_FormClosing({ if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
