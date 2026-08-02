# ==============================================================================
# CDS (CleanerDS) - Optimization Tool
# ==============================================================================

# Прячем консоль, если вдруг она открылась
$AsyncScript = {
    $code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32Utils" -PassThru
    $hwnd = (Get-Process -Id $PID).MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { $type::ShowWindow($hwnd, 0) }
}
try { &$AsyncScript } catch { }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Защита от двойного запуска
$script:MutexName = "Global\CleanerDS_Mutex"
$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, $script:MutexName, [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show("Программа CDS (CleanerDS) уже запущена!", "Внимание", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

# Системные пути
$script:AppLocal = [Environment]::GetFolderPath("LocalApplicationData")
$script:AppRoaming = [Environment]::GetFolderPath("ApplicationData")
$script:DiscordLocal = Join-Path -Path $script:AppLocal -ChildPath "Discord"
$script:DiscordRoaming = Join-Path -Path $script:AppRoaming -ChildPath "discord"
$script:BackupPath = Join-Path -Path $script:DiscordLocal -ChildPath "backup"

# Списки для сохранения
$script:KeepLocales = @("ru.pak", "en-US.pak")
$script:KeepModulePatterns = @("discord_desktop_core*", "discord_krisp*", "discord_modules*", "discord_utils*", "discord_voice*")

# --- ФУНКЦИИ ---

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    if ($null -ne $script:LogBox) {
        $color = switch ($Level) {
            "SUCCESS" { [System.Drawing.Color]::ForestGreen }
            "WARN"    { [System.Drawing.Color]::Gold }
            "ERROR"   { [System.Drawing.Color]::Crimson }
            Default   { [System.Drawing.Color]::Gainsboro }
        }
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.SelectionLength = 0
        $script:LogBox.SelectionColor = $color
        $script:LogBox.AppendText("[$timestamp] $Message`r`n")
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-Progress {
    param([int]$Value)
    if ($null -ne $script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Lock-UI {
    param([bool]$State)
    $script:PanelButtons.Enabled = -not $State
    [System.Windows.Forms.Application]::DoEvents()
}

function Find-DiscordApp {
    if (-not (Test-Path -Path $script:DiscordLocal)) { return $null }
    $folder = Get-ChildItem -Path $script:DiscordLocal -Directory -Filter "app-*" | 
              Sort-Object { try { [version]($_.Name -replace 'app-', '') } catch { [version]"0.0.0" } } -Descending | 
              Select-Object -First 1
    if ($folder) { return $folder.FullName }
    return $null
}

function Kill-Discord {
    $procs = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Log "Завершение работы Discord..." "WARN"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Update-DiscordStatus {
    $proc = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    $script:LblStatus.Text = if ($proc) { "Запущен" } else { "Остановлен" }
    $script:LblStatus.ForeColor = if ($proc) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Gray }
    
    $appFolder = Find-DiscordApp
    $script:LblVersion.Text = if ($appFolder) { (Split-Path -Path $appFolder -Leaf) -replace "app-", "" } else { "Не найден" }
}

function Run-Backup {
    Lock-UI $true
    Set-Progress 10
    
    try {
        $appFolder = Find-DiscordApp
        if (-not $appFolder) {
            Write-Log "Папка Discord не найдена для бэкапа." "ERROR"
            return
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $target = Join-Path -Path $script:BackupPath -ChildPath $timestamp
        New-Item -Path $target -ItemType Directory -Force | Out-Null
        Write-Log "Подготовка к резервному копированию..." "INFO"

        Set-Progress 30
        $modSrc = Join-Path -Path $appFolder -ChildPath "modules"
        if (Test-Path -Path $modSrc) { 
            Copy-Item -Path $modSrc -Destination "$target\modules" -Recurse -Force 
            Write-Log "Модули сохранены." "SUCCESS"
        }
        
        Set-Progress 70
        $locSrc = Join-Path -Path $appFolder -ChildPath "locales"
        if (Test-Path -Path $locSrc) { 
            Copy-Item -Path $locSrc -Destination "$target\locales" -Recurse -Force 
            Write-Log "Языковые файлы сохранены." "SUCCESS"
        }

        Set-Progress 100
        Write-Log "Бэкап успешно создан: $timestamp" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("Резервная копия создана в папке Backup!", "CDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } finally {
        Set-Progress 0
        Lock-UI $false
    }
}

function Run-Clean {
    if (-not $script:ChkLoc.Checked -and -not $script:ChkMod.Checked -and -not $script:ChkCac.Checked) {
        [System.Windows.Forms.MessageBox]::Show("Выберите хотя бы один пункт для очистки!", "Внимание", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    Lock-UI $true
    Kill-Discord
    Update-DiscordStatus
    Set-Progress 20

    try {
        $appFolder = Find-DiscordApp
        
        # Очистка локализаций
        if ($script:ChkLoc.Checked -and $appFolder) {
            $locDir = Join-Path -Path $appFolder -ChildPath "locales"
            if (Test-Path -Path $locDir) {
                Write-Log "Очистка лишних языков..." "INFO"
                Get-ChildItem -Path $locDir -File | Where-Object { $script:KeepLocales -notcontains $_.Name } | Remove-Item -Force
                Write-Log "Языки очищены." "SUCCESS"
            }
        }
        Set-Progress 50

        # Очистка модулей
        if ($script:ChkMod.Checked -and $appFolder) {
            $modDir = Join-Path -Path $appFolder -ChildPath "modules"
            if (Test-Path -Path $modDir) {
                Write-Log "Очистка мусорных модулей..." "INFO"
                Get-ChildItem -Path $modDir -Directory | ForEach-Object {
                    $mod = $_
                    $keep = $false
                    foreach ($pat in $script:KeepModulePatterns) { if ($mod.Name -like $pat) { $keep = $true; break } }
                    if (-not $keep) { 
                        Remove-Item -Path $mod.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Log "Удален модуль: $($mod.Name)" "INFO"
                    }
                }
                Write-Log "Очистка модулей завершена." "SUCCESS"
            }
        }
        Set-Progress 80

        # Очистка кэша
        if ($script:ChkCac.Checked) {
            Write-Log "Удаление кэша Discord..." "INFO"
            $caches = @("Cache", "Code Cache", "GPUCache", "DawnCache", "Session Storage")
            foreach ($c in $caches) {
                $cPath = Join-Path -Path $script:DiscordRoaming -ChildPath $c
                if (Test-Path -Path $cPath) {
                    Get-ChildItem -Path $cPath -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Log "Кэш и временные файлы удалены." "SUCCESS"
        }

        Set-Progress 100
        Write-Log "Оптимизация завершена!" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("Очистка и оптимизация Discord завершена успешно!", "CDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } finally {
        Set-Progress 0
        Lock-UI $false
    }
}

function Run-StartDiscord {
    $appFolder = Find-DiscordApp
    if ($appFolder) {
        $exePath = Join-Path -Path $appFolder -ChildPath "Discord.exe"
        if (Test-Path -Path $exePath) {
            Start-Process -FilePath $exePath
            Write-Log "Discord запущен." "SUCCESS"
            Start-Sleep -Seconds 2
            Update-DiscordStatus
        }
    } else {
        Write-Log "Discord.exe не найден!" "ERROR"
    }
}

function Show-Help([string]$Title, [string]$Text) {
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# --- ГРАФИЧЕСКИЙ ИНТЕРФЕЙС (GUI) ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "CDS (CleanerDS)"
$form.Size = New-Object System.Drawing.Size(900, 680)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(54, 57, 63)
$form.ForeColor = [System.Drawing.Color]::White

# Шапка
$pHeader = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 70); Dock = "Top"; BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37) }
$pHeader.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "CDS (CleanerDS)"; Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold); ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242); AutoSize = $true; Location = New-Object System.Drawing.Point(20, 15) }))

# Статус
$pStatus = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 45); Location = New-Object System.Drawing.Point(0, 70); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:LblStatus = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(145, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$script:LblVersion = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(345, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$pStatus.Controls.AddRange(@(
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Статус Discord:"; Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(20, 12); AutoSize = $true }),
    $script:LblStatus,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Версия:"; Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(270, 12); AutoSize = $true }),
    $script:LblVersion
))

# Опции
$pOptions = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(20, 125); Size = New-Object System.Drawing.Size(620, 110); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:ChkLoc = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Удалить неиспользуемые языки (locales)"; Location = New-Object System.Drawing.Point(15, 12); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$script:ChkMod = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Вырезать ненужные модули (modules)"; Location = New-Object System.Drawing.Point(15, 42); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$script:ChkCac = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Очистить кэш, CodeCache и Temp"; Location = New-Object System.Drawing.Point(15, 72); Size = New-Object System.Drawing.Size(380, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }

function Make-HelpBtn([int]$y, [string]$t, [string]$m) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = "Зачем?"; Location = New-Object System.Drawing.Point(510, $y); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
    $b.FlatAppearance.BorderSize = 0; $b.Add_Click({ Show-Help $t $m }); return $b
}
$pOptions.Controls.AddRange(@($script:ChkLoc, (Make-HelpBtn 10 "Языки" "Удаляет более 70 лишних языковых пакетов, оставляя только RU и EN. Это ускоряет старт."), 
                              $script:ChkMod, (Make-HelpBtn 40 "Модули" "Удаляет мусорные модули телеметрии и игр, оставляя звук и Krisp."), 
                              $script:ChkCac, (Make-HelpBtn 70 "Кэш" "Чистит папку Cache, GPUCache и CodeCache, освобождая сотни мегабайт.")))

# Лог
$script:LogBox = New-Object System.Windows.Forms.RichTextBox -Property @{ Location = New-Object System.Drawing.Point(20, 245); Size = New-Object System.Drawing.Size(620, 355); BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37); ForeColor = [System.Drawing.Color]::Gainsboro; Font = New-Object System.Drawing.Font("Consolas", 9.5); ReadOnly = $true; BorderStyle = "None" }

# Правая панель кнопок (для блокировки во время работы)
$script:PanelButtons = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(660, 125); Size = New-Object System.Drawing.Size(200, 475) }

function Make-Btn([string]$text, [int]$y, $action, $color = [System.Drawing.Color]::FromArgb(79, 84, 92)) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = $text; Location = New-Object System.Drawing.Point(0, $y); Size = New-Object System.Drawing.Size(200, 42); BackColor = $color; ForeColor = "White"; FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
    $b.FlatAppearance.BorderSize = 0; $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); $b.Add_Click($action); return $b
}
$script:PanelButtons.Controls.AddRange(@(
    (Make-Btn "Создать Backup" 0 { Run-Backup }),
    (Make-Btn "Очистить Discord" 52 { Run-Clean } ([System.Drawing.Color]::FromArgb(237, 66, 69))),
    (Make-Btn "Запустить Discord" 104 { Run-StartDiscord } ([System.Drawing.Color]::FromArgb(57, 105, 54))),
    (Make-Btn "Выход" 425 { $form.Close() })
))

# Прогресс бар
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = New-Object System.Drawing.Point(0, 615); Size = New-Object System.Drawing.Size(900, 10); Dock = "Bottom" }

$form.Controls.AddRange(@($pHeader, $pStatus, $pOptions, $script:LogBox, $script:PanelButtons, $script:ProgressBar))
$form.Add_Shown({ Write-Log "CDS (CleanerDS) успешно загружен и готов." "SUCCESS"; Update-DiscordStatus })
$form.Add_FormClosing({ if ($null -ne $script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
