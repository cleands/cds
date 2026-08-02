# ==============================================================================
# CLEANER DS (CDS) - ULTIMATE EDITION
# ==============================================================================

# ------------------------------------------------------------------------------
# БЛОК 1: ИНИЦИАЛИЗАЦИЯ И СКРЫТИЕ КОНСОЛИ
# ------------------------------------------------------------------------------
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
$script:Mutex = New-Object System.Threading.Mutex($true, "Global\CleanerDS_Mutex", [ref]$script:MutexCreated)
if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show("Программа уже запущена!", "Внимание", 0, 48)
    exit
}

# Системные переменные
$script:AppLocal = [Environment]::GetFolderPath("LocalApplicationData")
$script:AppRoaming = [Environment]::GetFolderPath("ApplicationData")
$script:DiscordLocal = Join-Path -Path $script:AppLocal -ChildPath "Discord"
$script:DiscordRoaming = Join-Path -Path $script:AppRoaming -ChildPath "discord"
$script:BackupPath = Join-Path -Path $script:DiscordLocal -ChildPath "backup"

$script:KeepLocales = @("ru.pak", "en-US.pak")
$script:KeepModules = @("discord_desktop_core*", "discord_krisp*", "discord_modules*", "discord_utils*", "discord_voice*")

# ------------------------------------------------------------------------------
# БЛОК 2: УТИЛИТЫ И ЛОГИКА
# ------------------------------------------------------------------------------
function Write-Log([string]$Msg, [string]$Lvl = "INFO") {
    $ts = Get-Date -Format "HH:mm:ss"
    if ($script:LogBox) {
        $color = switch ($Lvl) {
            "SUCCESS" { [System.Drawing.Color]::LimeGreen }
            "WARN"    { [System.Drawing.Color]::Gold }
            "ERROR"   { [System.Drawing.Color]::Tomato }
            Default   { [System.Drawing.Color]::WhiteSmoke }
        }
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.SelectionLength = 0
        $script:LogBox.SelectionColor = $color
        $script:LogBox.AppendText("[$ts] $Msg`r`n")
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-Progress([int]$Val) {
    if ($script:ProgressBar) { $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Val)) }
    [System.Windows.Forms.Application]::DoEvents()
}

function Find-DiscordApp {
    if (-not (Test-Path $script:DiscordLocal)) { return $null }
    return (Get-ChildItem -Path $script:DiscordLocal -Directory -Filter "app-*" | Sort-Object Name -Descending | Select-Object -First 1).FullName
}

function Update-UI {
    $proc = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    $script:LblStatus.Text = if ($proc) { "Запущен" } else { "Остановлен" }
    $script:LblStatus.ForeColor = if ($proc) { [System.Drawing.Color]::LimeGreen } else { [System.Drawing.Color]::Gray }
    
    $appFolder = Find-DiscordApp
    $script:LblVersion.Text = if ($appFolder) { (Split-Path $appFolder -Leaf) -replace "app-", "" } else { "Не найден" }

    if ((Test-Path $script:BackupPath) -and ((Get-ChildItem $script:BackupPath -Directory).Count -gt 0)) {
        $count = (Get-ChildItem $script:BackupPath -Directory).Count
        $script:LblBackup.Text = "Доступно ($count)"
        $script:LblBackup.ForeColor = [System.Drawing.Color]::LimeGreen
    } else {
        $script:LblBackup.Text = "Отсутствует"
        $script:LblBackup.ForeColor = [System.Drawing.Color]::Tomato
    }
}

function Stop-DiscordProcess {
    $procs = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Log "Закрытие Discord..." "WARN"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# ------------------------------------------------------------------------------
# БЛОК 3: ОСНОВНЫЕ ОПЕРАЦИИ (БЭКАП И ОЧИСТКА)
# ------------------------------------------------------------------------------
function Run-Backup {
    $script:MainPanel.Enabled = $false
    Set-Progress 10
    try {
        $app = Find-DiscordApp
        if (-not $app) { Write-Log "Discord не найден!" "ERROR"; return $false }

        $ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $tgt = Join-Path $script:BackupPath $ts
        New-Item -Path $tgt -ItemType Directory -Force | Out-Null
        
        Write-Log "Создание бэкапа: $ts" "INFO"
        if (Test-Path "$app\modules") { Copy-Item "$app\modules" "$tgt\modules" -Recurse -Force }
        Set-Progress 50
        if (Test-Path "$app\locales") { Copy-Item "$app\locales" "$tgt\locales" -Recurse -Force }
        
        Write-Log "Бэкап успешно создан!" "SUCCESS"
        Set-Progress 100
        return $true
    } finally {
        $script:MainPanel.Enabled = $true
        Set-Progress 0; Update-UI
    }
}

function Run-Clean {
    if (-not $script:ChkLoc.Checked -and -not $script:ChkMod.Checked -and -not $script:ChkCac.Checked) {
        [System.Windows.Forms.MessageBox]::Show("Выберите пункты для очистки!", "Ошибка", 0, 48)
        return
    }

    if (-not (Test-Path $script:BackupPath)) {
        if ([System.Windows.Forms.MessageBox]::Show("Бэкап отсутствует. Создать?", "Внимание", 4, 32) -eq "Yes") {
            if (-not (Run-Backup)) { return }
        } else { Write-Log "Очистка отменена." "WARN"; return }
    }

    $script:MainPanel.Enabled = $false
    Stop-DiscordProcess
    Update-UI
    Set-Progress 20

    try {
        $app = Find-DiscordApp
        if ($script:ChkLoc.Checked -and $app) {
            Write-Log "Очистка лишних языков..." "INFO"
            Get-ChildItem "$app\locales" -File -ErrorAction SilentlyContinue | Where-Object { $script:KeepLocales -notcontains $_.Name } | Remove-Item -Force
        }
        Set-Progress 50

        if ($script:ChkMod.Checked -and $app) {
            Write-Log "Очистка тяжелых модулей..." "INFO"
            Get-ChildItem "$app\modules" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $m = $_; $keep = $false
                foreach ($p in $script:KeepModules) { if ($m.Name -like $p) { $keep = $true; break } }
                if (-not $keep) { Remove-Item $m.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        Set-Progress 80

        if ($script:ChkCac.Checked) {
            Write-Log "Очистка кэша..." "INFO"
            @("Cache", "Code Cache", "GPUCache", "DawnCache") | ForEach-Object {
                $cp = Join-Path $script:DiscordRoaming $_
                if (Test-Path $cp) { Remove-Item $cp -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        
        Write-Log "Discord успешно очищен и оптимизирован!" "SUCCESS"
        Set-Progress 100
        [System.Windows.Forms.MessageBox]::Show("Очистка завершена!", "Готово", 0, 64)
    } finally {
        $script:MainPanel.Enabled = $true
        Set-Progress 0; Update-UI
    }
}

# ------------------------------------------------------------------------------
# БЛОК 4: ГРАФИЧЕСКИЙ ИНТЕРФЕЙС (GUI)
# ------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "CleanerDS - Ultimate"
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(44, 47, 51)
$form.ForeColor = [System.Drawing.Color]::White

$script:MainPanel = New-Object System.Windows.Forms.Panel
$script:MainPanel.Dock = "Fill"
$form.Controls.Add($script:MainPanel)

# Заголовок
$lblTitle = New-Object System.Windows.Forms.Label -Property @{ Text = "CLEANER DS"; Font = New-Object System.Drawing.Font("Segoe UI Black", 24); ForeColor = [System.Drawing.Color]::FromArgb(114, 137, 218); Location = New-Object System.Drawing.Point(20, 15); AutoSize = $true }
$script:MainPanel.Controls.Add($lblTitle)

# Статус бар
$script:LblStatus = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(120, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$script:LblBackup = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(340, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$script:LblVersion = New-Object System.Windows.Forms.Label -Property @{ Location = New-Object System.Drawing.Point(580, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$script:MainPanel.Controls.AddRange(@(
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Discord:"; Location = New-Object System.Drawing.Point(25, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10, 1) }), $script:LblStatus,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Бэкапы:"; Location = New-Object System.Drawing.Point(240, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10, 1) }), $script:LblBackup,
    (New-Object System.Windows.Forms.Label -Property @{ Text = "Версия:"; Location = New-Object System.Drawing.Point(490, 70); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10, 1) }), $script:LblVersion
))

# Чекбоксы
$pOpts = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(25, 110); Size = New-Object System.Drawing.Size(600, 100); BackColor = [System.Drawing.Color]::FromArgb(35, 39, 42) }
$script:ChkLoc = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Языки (locales) - Оставить только RU/EN"; Location = New-Object System.Drawing.Point(15, 15); Size = New-Object System.Drawing.Size(500, 20); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$script:ChkMod = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Модули (modules) - Вырезать телеметрию и игры"; Location = New-Object System.Drawing.Point(15, 40); Size = New-Object System.Drawing.Size(500, 20); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$script:ChkCac = New-Object System.Windows.Forms.CheckBox -Property @{ Text = "Кэш (Cache) - Очистить временные файлы"; Location = New-Object System.Drawing.Point(15, 65); Size = New-Object System.Drawing.Size(500, 20); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 10) }
$pOpts.Controls.AddRange(@($script:ChkLoc, $script:ChkMod, $script:ChkCac))
$script:MainPanel.Controls.Add($pOpts)

# Консоль
$script:LogBox = New-Object System.Windows.Forms.RichTextBox -Property @{ Location = New-Object System.Drawing.Point(25, 230); Size = New-Object System.Drawing.Size(600, 340); BackColor = [System.Drawing.Color]::FromArgb(35, 39, 42); ForeColor = [System.Drawing.Color]::WhiteSmoke; Font = New-Object System.Drawing.Font("Consolas", 10); ReadOnly = $true; BorderStyle = "None" }
$script:MainPanel.Controls.Add($script:LogBox)

# Кнопки управления
function Make-Btn($txt, $y, $act, $col = [System.Drawing.Color]::FromArgb(88, 101, 242)) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = $txt; Location = New-Object System.Drawing.Point(645, $y); Size = New-Object System.Drawing.Size(215, 45); BackColor = $col; ForeColor = "White"; FlatStyle = "Flat"; Cursor = "Hand"; Font = New-Object System.Drawing.Font("Segoe UI", 10, 1) }
    $b.FlatAppearance.BorderSize = 0; $b.Add_Click($act); return $b
}
$script:MainPanel.Controls.AddRange(@(
    (Make-Btn "Создать Бэкап" 110 { [void](Run-Backup) } ([System.Drawing.Color]::FromArgb(67, 181, 129))),
    (Make-Btn "МОЩНАЯ ОЧИСТКА" 165 { Run-Clean } ([System.Drawing.Color]::FromArgb(240, 71, 71))),
    (Make-Btn "Открыть папку бэкапов" 230 { try { Start-Process "explorer.exe" "`"$script:BackupPath`"" } catch {} } ([System.Drawing.Color]::FromArgb(114, 137, 218))),
    (Make-Btn "Запустить Discord" 460 { $exe = "$((Find-DiscordApp))\Discord.exe"; if(Test-Path $exe){ Start-Process $exe; Write-Log "Discord запущен" "SUCCESS"; Start-Sleep -s 2; Update-UI } } ([System.Drawing.Color]::FromArgb(67, 181, 129))),
    (Make-Btn "Выход" 525 { $form.Close() } ([System.Drawing.Color]::FromArgb(116, 127, 141)))
))

# Прогресс бар
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = New-Object System.Drawing.Point(0, 595); Size = New-Object System.Drawing.Size(900, 15); Dock = "Bottom" }
$form.Controls.Add($script:ProgressBar)

$form.Add_Shown({ Write-Log "Система загружена. Готово к работе." "SUCCESS"; Update-UI })
$form.Add_FormClosing({ if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
