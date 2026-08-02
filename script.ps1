# ==============================================================================
# ClientRDS
# ==============================================================================

# Скрытие консоли PowerShell
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

# Single Instance Check
$script:AppMutexName = "Global\ClientRDS_SingleInstance_Mutex"
$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, $script:AppMutexName, [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show("ClientRDS уже запущен!", "ClientRDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

# Пути
$script:LocalAppData = [Environment]::GetFolderPath("LocalApplicationData")
$script:AppData      = [Environment]::GetFolderPath("ApplicationData")
$script:DiscordPath   = Join-Path -Path $script:LocalAppData -ChildPath "Discord"
$script:CachePath     = Join-Path -Path $script:AppData      -ChildPath "discord\Cache"
$script:CodeCachePath = Join-Path -Path $script:AppData      -ChildPath "discord\Code Cache"
$script:GPUCachePath  = Join-Path -Path $script:AppData      -ChildPath "discord\GPUCache"
$script:BackupPath    = Join-Path -Path $script:DiscordPath  -ChildPath "backup"

$script:KeepLocales = @("ru.pak", "en-US.pak")
$script:KeepModulePatterns = @("discord_desktop_core*", "discord_krisp*", "discord_modules*", "discord_utils*", "discord_voice*")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    if ($null -ne $script:RichTextBoxLog) {
        $color = switch ($Level) {
            "SUCCESS" { [System.Drawing.Color]::ForestGreen }
            "WARN"    { [System.Drawing.Color]::Gold }
            "ERROR"   { [System.Drawing.Color]::Crimson }
            Default   { [System.Drawing.Color]::Gainsboro }
        }
        $script:RichTextBoxLog.SelectionStart = $script:RichTextBoxLog.TextLength
        $script:RichTextBoxLog.SelectionLength = 0
        $script:RichTextBoxLog.SelectionColor = $color
        $script:RichTextBoxLog.AppendText("[$timestamp] $Message`r`n")
        $script:RichTextBoxLog.ScrollToCaret()
    }
}

function Update-ProgressBar {
    param([int]$Value)
    if ($null -ne $script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Find-Discord {
    if (-not (Test-Path -Path $script:DiscordPath)) { return $null }
    $appFolder = Get-ChildItem -Path $script:DiscordPath -Directory -Filter "app-*" | Sort-Object { 
        try { [version]($_.Name -replace 'app-', '') } catch { [version]"0.0.0" } 
    } -Descending | Select-Object -First 1
    return $appFolder.FullName
}

function Stop-Discord {
    $processes = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Log -Message "Завершение процессов Discord..." -Level "WARN"
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
            Write-Log -Message "Discord запущен." -Level "SUCCESS"
        }
    }
    Update-Status
}

function Create-Backup {
    param([bool]$ShowDialogs = $true)
    Update-ProgressBar -Value 20
    $appFolder = Find-Discord
    if (-not $appFolder) { Update-ProgressBar -Value 0; return $false }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $targetFolder = Join-Path -Path $script:BackupPath -ChildPath $timestamp
    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null

    $modulesSrc = Join-Path -Path $appFolder -ChildPath "modules"
    if (Test-Path -Path $modulesSrc) { Copy-Item -Path $modulesSrc -Destination "$targetFolder\modules" -Recurse -Force }
    
    $localesSrc = Join-Path -Path $appFolder -ChildPath "locales"
    if (Test-Path -Path $localesSrc) { Copy-Item -Path $localesSrc -Destination "$targetFolder\locales" -Recurse -Force }

    Update-ProgressBar -Value 100
    Write-Log -Message "Резервная копия создана: $timestamp" -Level "SUCCESS"
    if ($ShowDialogs) { [System.Windows.Forms.MessageBox]::Show("Резервная копия создана!", "ClientRDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) }
    Update-Status
    Update-ProgressBar -Value 0
    return $true
}

function Start-CleaningProcess {
    if (-not $script:ChkLocales.Checked -and -not $script:ChkModules.Checked -and -not $script:ChkCache.Checked) {
        [System.Windows.Forms.MessageBox]::Show("Выберите элементы для очистки!", "Предупреждение", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    Stop-Discord
    Update-ProgressBar -Value 30

    $appFolder = Find-Discord
    if ($appFolder) {
        if ($script:ChkLocales.Checked) {
            $localesDir = Join-Path -Path $appFolder -ChildPath "locales"
            if (Test-Path -Path $localesDir) {
                Get-ChildItem -Path $localesDir -File | Where-Object { $script:KeepLocales -notcontains $_.Name } | Remove-Item -Force
                Write-Log -Message "Языковые файлы очищены." -Level "INFO"
            }
        }
        Update-ProgressBar -Value 60

        if ($script:ChkModules.Checked) {
            $modulesDir = Join-Path -Path $appFolder -ChildPath "modules"
            if (Test-Path -Path $modulesDir) {
                Get-ChildItem -Path $modulesDir -Directory | ForEach-Object {
                    $mod = $_
                    $keep = $false
                    foreach ($pat in $script:KeepModulePatterns) { if ($mod.Name -like $pat) { $keep = $true; break } }
                    if (-not $keep) { Remove-Item -Path $mod.FullName -Recurse -Force; Write-Log -Message "Удален модуль: $($mod.Name)" -Level "INFO" }
                }
            }
        }
    }
    Update-ProgressBar -Value 80

    if ($script:ChkCache.Checked) {
        @($script:CachePath, $script:CodeCachePath, $script:GPUCachePath) | ForEach-Object {
            if (Test-Path -Path $_) { Get-ChildItem -Path $_ -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-Log -Message "Кэш и временные файлы очищены." -Level "INFO"
    }

    Update-ProgressBar -Value 100
    Write-Log -Message "Оптимизация завершена успешно!" -Level "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Оптимизация завершена!", "ClientRDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Update-Status
    Update-ProgressBar -Value 0
}

function Update-Status {
    $process = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    $script:LblStatusDiscord.Text = if ($process) { "Запущен" } else { "Остановлен" }
    $script:LblStatusDiscord.ForeColor = if ($process) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Gray }

    $appFolder = Find-Discord
    $script:LblVersion.Text = if ($appFolder) { (Split-Path -Path $appFolder -Leaf) -replace "app-", "" } else { "Не найден" }
}

function Show-WhyInfo {
    param([string]$Title, [string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# --- GUI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "ClientRDS"
$form.Size = New-Object System.Drawing.Size(900, 680)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(54, 57, 63)
$form.ForeColor = [System.Drawing.Color]::White

# Шапка
$panelHeader = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 70); Dock = "Top"; BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37) }
$lblTitle = New-Object System.Windows.Forms.Label -Property @{ Text = "ClientRDS"; Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold); ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242); AutoSize = $true; Location = New-Object System.Drawing.Point(20, 15) }
$panelHeader.Controls.Add($lblTitle)

# Панель статуса
$panelStatus = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 45); Location = New-Object System.Drawing.Point(0, 70); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:LblStatusDiscord = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(145, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$script:LblVersion = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(345, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$panelStatus.Controls.AddRange(@(
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Статус Discord:"; Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(20, 12); AutoSize = $true }),
    $script:LblStatusDiscord,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Версия:"; Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(270, 12); AutoSize = $true }),
    $script:LblVersion
))

# Опции
$panelOptions = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(20, 125); Size = New-Object System.Drawing.Size(620, 110); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }

$script:ChkLocales = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Удалить неиспользуемые языки (locales)"; Location = New-Object System.Drawing.Point(15, 12); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyLoc = New-Object System.Windows.Forms.Button -Property @{ Text = "Зачем?"; Location = New-Object System.Drawing.Point(510, 10); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyLoc.FlatAppearance.BorderSize = 0
$btnWhyLoc.Add_Click({ Show-WhyInfo -Title "Локации" -Message "Удаляет 70+ лишних .pak локализаций Chromium, ускоряя запуск." })

$script:ChkModules = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Вырезать ненужные модули (modules)"; Location = New-Object System.Drawing.Point(15, 42); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyMod = New-Object System.Windows.Forms.Button -Property @{ Text = "Зачем?"; Location = New-Object System.Drawing.Point(510, 40); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyMod.FlatAppearance.BorderSize = 0
$btnWhyMod.Add_Click({ Show-WhyInfo -Title "Модули" -Message "Вырезает оверлеи и лишнюю телеметрию, оставляя звук и Krisp." })

$script:ChkCache = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Очистить кэш, CodeCache и Temp"; Location = New-Object System.Drawing.Point(15, 72); Size = New-Object System.Drawing.Size(380, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyCache = New-Object System.Windows.Forms.Button -Property @{ Text = "Зачем?"; Location = New-Object System.Drawing.Point(510, 70); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyCache.FlatAppearance.BorderSize = 0
$btnWhyCache.Add_Click({ Show-WhyInfo -Title "Кэш" -Message "Удаляет скомпилированные скрипты и кэшированные медиафайлы." })

$panelOptions.Controls.AddRange(@($script:ChkLocales, $btnWhyLoc, $script:ChkModules, $btnWhyMod, $script:ChkCache, $btnWhyCache))

# Консоль / Логи
$script:RichTextBoxLog = New-Object System.Windows.Forms.RichTextBox -Property @{ Location = New-Object System.Drawing.Point(20, 245); Size = New-Object System.Drawing.Size(620, 355); BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37); ForeColor = [System.Drawing.Color]::Gainsboro; Font = New-Object System.Drawing.Font("Consolas", 9.5); ReadOnly = $true; BorderStyle = "None" }

# Правые кнопки
$panelButtons = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(660, 125); Size = New-Object System.Drawing.Size(200, 475) }

function Make-Btn([string]$text, [int]$y, $action, $color = [System.Drawing.Color]::FromArgb(79, 84, 92)) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = $text; Location = New-Object System.Drawing.Point(0, $y); Size = New-Object System.Drawing.Size(200, 42); BackColor = $color; ForeColor = "White"; FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $b.Add_Click($action)
    return $b
}

$panelButtons.Controls.AddRange(@(
    (Make-Btn "Создать Backup" 0 { Create-Backup }),
    (Make-Btn "Очистить Discord" 52 { Start-CleaningProcess } ([System.Drawing.Color]::FromArgb(237, 66, 69))),
    (Make-Btn "Запустить Discord" 104 { Start-Discord } ([System.Drawing.Color]::FromArgb(57, 105, 54))),
    (Make-Btn "Выход" 425 { $form.Close() })
))

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = New-Object System.Drawing.Point(0, 615); Size = New-Object System.Drawing.Size(900, 10); Dock = "Bottom" }

$form.Controls.AddRange(@($panelHeader, $panelStatus, $panelOptions, $script:RichTextBoxLog, $panelButtons, $script:ProgressBar))
$form.Add_Shown({ Write-Log -Message "ClientRDS готов к работе." -Level "SUCCESS"; Update-Status })
$form.Add_FormClosing({ if ($null -ne $script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
