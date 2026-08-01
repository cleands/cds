# ==============================================================================
# CleanerDS — Discord Optimization Tool (Online Executable PS1)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. МГНОВЕННОЕ СКРЫТИЕ ОКНА КОНСОЛИ (ПОВАРЁШКИ)
# ------------------------------------------------------------------------------
$AsyncScript = {
    $code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32Utils" -PassThru
    $hwnd = (Get-Process -Id $PID).MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        $type::ShowWindow($hwnd, 0) # 0 = SW_HIDE
    }
}
try { &$AsyncScript } catch { }

# Загрузка сборки Windows Forms & Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------------------------
# 2. МУТЕКС (ЗАЩИТА ОТ ПОВТОРНОГО ЗАПУСКА)
# ------------------------------------------------------------------------------
$script:AppMutexName = "Global\CleanerDS_SingleInstance_Mutex"
$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, $script:AppMutexName, [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show(
        "Приложение CleanerDS уже запущено!",
        "Предупреждение",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit
}

# ------------------------------------------------------------------------------
# 3. СИСТЕМНЫЕ ПУТИ И ПЕРЕМЕННЫЕ
# ------------------------------------------------------------------------------
$script:LocalAppData = [Environment]::GetFolderPath("LocalApplicationData")
$script:AppData      = [Environment]::GetFolderPath("ApplicationData")

$script:DiscordPath   = Join-Path -Path $script:LocalAppData -ChildPath "Discord"
$script:CachePath     = Join-Path -Path $script:AppData      -ChildPath "discord\Cache"
$script:CodeCachePath = Join-Path -Path $script:AppData      -ChildPath "discord\Code Cache"
$script:GPUCachePath  = Join-Path -Path $script:AppData      -ChildPath "discord\GPUCache"
$script:BackupPath    = Join-Path -Path $script:DiscordPath  -ChildPath "backup"

$script:KeepLocales = @("ru.pak", "en-US.pak")
$script:KeepModulePatterns = @(
    "discord_desktop_core*",
    "discord_krisp*",
    "discord_modules*",
    "discord_utils*",
    "discord_voice*"
)

# ------------------------------------------------------------------------------
# 4. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ------------------------------------------------------------------------------
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
    if ($ShowDialogs) { 
        [System.Windows.Forms.MessageBox]::Show("Резервная копия успешно создана!", "Успех", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) 
    }
    Update-Status
    Update-ProgressBar -Value 0
    return $true
}

function Start-CleaningProcess {
    if (-not $script:ChkLocales.Checked -and -not $script:ChkModules.Checked -and -not $script:ChkCache.Checked) {
        [System.Windows.Forms.MessageBox]::Show("Выберите хотя бы один элемент для очистки!", "Предупреждение", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    Stop-Discord
    Update-ProgressBar -Value 30

    $appFolder = Find-Discord
    if ($appFolder) {
        # Очистка языков (Locales)
        if ($script:ChkLocales.Checked) {
            $localesDir = Join-Path -Path $appFolder -ChildPath "locales"
            if (Test-Path -Path $localesDir) {
                Get-ChildItem -Path $localesDir -File | Where-Object { $script:KeepLocales -notcontains $_.Name } | Remove-Item -Force
                Write-Log -Message "Неиспользуемые языковые пакеты удалены." -Level "INFO"
            }
        }
        Update-ProgressBar -Value 60

        # Очистка модулей (Modules)
        if ($script:ChkModules.Checked) {
            $modulesDir = Join-Path -Path $appFolder -ChildPath "modules"
            if (Test-Path -Path $modulesDir) {
                Get-ChildItem -Path $modulesDir -Directory | ForEach-Object {
                    $mod = $_
                    $keep = $false
                    foreach ($pat in $script:KeepModulePatterns) { if ($mod.Name -like $pat) { $keep = $true; break } }
                    if (-not $keep) { 
                        Remove-Item -Path $mod.FullName -Recurse -Force
                        Write-Log -Message "Удалён лишний модуль: $($mod.Name)" -Level "INFO" 
                    }
                }
            }
        }
    }
    Update-ProgressBar -Value 80

    # Очистка Кэша и Temp
    if ($script:ChkCache.Checked) {
        @($script:CachePath, $script:CodeCachePath, $script:GPUCachePath) | ForEach-Object {
            if (Test-Path -Path $_) { 
                Get-ChildItem -Path $_ -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 
            }
        }
        Write-Log -Message "Кэш, CodeCache и временные файлы Discord очищены." -Level "INFO"
    }

    Update-ProgressBar -Value 100
    Write-Log -Message "Оптимизация Discord завершена!" -Level "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Discord успешно оптимизирован!", "Успех", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
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

# ------------------------------------------------------------------------------
# 5. ИНТЕРФЕЙС WINDOWS FORMS (GUI)
# ------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "CleanerDS — Discord Optimization Tool"
$form.Size = New-Object System.Drawing.Size(900, 680)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(54, 57, 63)
$form.ForeColor = [System.Drawing.Color]::White

# Шапка
$panelHeader = New-Object System.Windows.Forms.Panel
$panelHeader.Size = New-Object System.Drawing.Size(900, 70)
$panelHeader.Dock = "Top"
$panelHeader.BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "ClientRDS"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$panelHeader.Controls.Add($lblTitle)

# Панель Статусов
$panelStatus = New-Object System.Windows.Forms.Panel
$panelStatus.Size = New-Object System.Drawing.Size(900, 45)
$panelStatus.Location = New-Object System.Drawing.Point(0, 70)
$panelStatus.BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54)

$lblTagDs = New-Object System.Windows.Forms.Label
$lblTagDs.Text = "Статус Discord:"
$lblTagDs.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTagDs.Location = New-Object System.Drawing.Point(20, 12)
$lblTagDs.AutoSize = $true

$script:LblStatusDiscord = New-Object System.Windows.Forms.Label
$script:LblStatusDiscord.Text = "Проверка..."
$script:LblStatusDiscord.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:LblStatusDiscord.Location = New-Object System.Drawing.Point(135, 12)
$script:LblStatusDiscord.AutoSize = $true

$lblTagVer = New-Object System.Windows.Forms.Label
$lblTagVer.Text = "Версия:"
$lblTagVer.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTagVer.Location = New-Object System.Drawing.Point(270, 12)
$lblTagVer.AutoSize = $true

$script:LblVersion = New-Object System.Windows.Forms.Label
$script:LblVersion.Text = "..."
$script:LblVersion.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:LblVersion.Location = New-Object System.Drawing.Point(335, 12)
$script:LblVersion.AutoSize = $true

$panelStatus.Controls.AddRange(@($lblTagDs, $script:LblStatusDiscord, $lblTagVer, $script:LblVersion))

# Панель Опций
$panelOptions = New-Object System.Windows.Forms.Panel
$panelOptions.Location = New-Object System.Drawing.Point(20, 125)
$panelOptions.Size = New-Object System.Drawing.Size(620, 110)
$panelOptions.BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54)

# 1. Языки
$script:ChkLocales = New-Object System.Windows.Forms.CheckBox
$script:ChkLocales.Text = "Удалить неиспользуемые языки (locales)"
$script:ChkLocales.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:ChkLocales.Location = New-Object System.Drawing.Point(15, 12)
$script:ChkLocales.Size = New-Object System.Drawing.Size(350, 25)
$script:ChkLocales.Checked = $true

$btnWhyLoc = New-Object System.Windows.Forms.Button
$btnWhyLoc.Text = "Зачем?"
$btnWhyLoc.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnWhyLoc.Location = New-Object System.Drawing.Point(510, 10)
$btnWhyLoc.Size = New-Object System.Drawing.Size(95, 26)
$btnWhyLoc.BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$btnWhyLoc.FlatStyle = "Flat"
$btnWhyLoc.FlatAppearance.BorderSize = 0
$btnWhyLoc.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnWhyLoc.Add_Click({ 
    Show-WhyInfo -Title "Зачем удалять языки?" -Message "Discord создан на движке Chromium и качает свыше 70 локализаций (.pak файлов).`n`nУдаление языков кроме ru/en уменьшает размер приложения и снижает нагрузку на диск." 
})

# 2. Модули
$script:ChkModules = New-Object System.Windows.Forms.CheckBox
$script:ChkModules.Text = "Вырезать ненужные модули (modules)"
$script:ChkModules.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:ChkModules.Location = New-Object System.Drawing.Point(15, 42)
$script:ChkModules.Size = New-Object System.Drawing.Size(350, 25)
$script:ChkModules.Checked = $true

$btnWhyMod = New-Object System.Windows.Forms.Button
$btnWhyMod.Text = "Зачем?"
$btnWhyMod.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnWhyMod.Location = New-Object System.Drawing.Point(510, 40)
$btnWhyMod.Size = New-Object System.Drawing.Size(95, 26)
$btnWhyMod.BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$btnWhyMod.FlatStyle = "Flat"
$btnWhyMod.FlatAppearance.BorderSize = 0
$btnWhyMod.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnWhyMod.Add_Click({ 
    Show-WhyInfo -Title "Зачем убирать модули?" -Message "Вырезает оверлеи, проверки орфографии и фоновую телеметрию.`n`nОстаются только критические компоненты: голосовой движок (voice), шумодав Krisp и системное ядро." 
})

# 3. Кэш
$script:ChkCache = New-Object System.Windows.Forms.CheckBox
$script:ChkCache.Text = "Очистить кэш, CodeCache и Temp"
$script:ChkCache.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:ChkCache.Location = New-Object System.Drawing.Point(15, 72)
$script:ChkCache.Size = New-Object System.Drawing.Size(380, 25)
$script:ChkCache.Checked = $true

$btnWhyCache = New-Object System.Windows.Forms.Button
$btnWhyCache.Text = "Зачем?"
$btnWhyCache.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnWhyCache.Location = New-Object System.Drawing.Point(510, 70)
$btnWhyCache.Size = New-Object System.Drawing.Size(95, 26)
$btnWhyCache.BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$btnWhyCache.FlatStyle = "Flat"
$btnWhyCache.FlatAppearance.BorderSize = 0
$btnWhyCache.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnWhyCache.Add_Click({ 
    Show-WhyInfo -Title "Зачем чистить кэш?" -Message "Удаляет накопившиеся аватарки, гифки, картинки из чатов и скомпилированные скрипты Chromium, освобождая место на накопителе." 
})

$panelOptions.Controls.AddRange(@($script:ChkLocales, $btnWhyLoc, $script:ChkModules, $btnWhyMod, $script:ChkCache, $btnWhyCache))

# Поле Логов
$script:RichTextBoxLog = New-Object System.Windows.Forms.RichTextBox
$script:RichTextBoxLog.Location = New-Object System.Drawing.Point(20, 245)
$script:RichTextBoxLog.Size = New-Object System.Drawing.Size(620, 355)
$script:RichTextBoxLog.BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37)
$script:RichTextBoxLog.ForeColor = [System.Drawing.Color]::Gainsboro
$script:RichTextBoxLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$script:RichTextBoxLog.ReadOnly = $true
$script:RichTextBoxLog.BorderStyle = "None"

# Правая Панель Кнопок
$panelButtons = New-Object System.Windows.Forms.Panel
$panelButtons.Location = New-Object System.Drawing.Point(660, 125)
$panelButtons.Size = New-Object System.Drawing.Size(200, 475)

function Make-Btn([string]$text, [int]$y, $action, $color = [System.Drawing.Color]::FromArgb(79, 84, 92)) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point(0, $y)
    $b.Size = New-Object System.Drawing.Size(200, 42)
    $b.BackColor = $color
    $b.ForeColor = "White"
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click($action)
    return $b
}

$btnBackup  = Make-Btn "Создать Backup"   0   { Create-Backup }
$btnClean   = Make-Btn "Очистить Discord"  52  { Start-CleaningProcess } ([System.Drawing.Color]::FromArgb(237, 66, 69))
$btnStart   = Make-Btn "Запустить Discord" 104 { Start-Discord } ([System.Drawing.Color]::FromArgb(57, 105, 54))
$btnExit    = Make-Btn "Выход"             425 { $form.Close() }

$panelButtons.Controls.AddRange(@($btnBackup, $btnClean, $btnStart, $btnExit))

# Прогресс-бар
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(0, 615)
$script:ProgressBar.Size = New-Object System.Drawing.Size(900, 10)
$script:ProgressBar.Dock = "Bottom"

# Сборка
$form.Controls.AddRange(@($panelHeader, $panelStatus, $panelOptions, $script:RichTextBoxLog, $panelButtons, $script:ProgressBar))

$form.Add_Shown({
    Write-Log -Message "CleanerDS успешно запущен." -Level "SUCCESS"
    Update-Status
})

$form.Add_FormClosing({
    if ($null -ne $script:Mutex) {
        $script:Mutex.ReleaseMutex()
        $script:Mutex.Dispose()
    }
})

# Запуск
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
