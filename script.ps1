# ==============================================================================
# CleanerDS — Discord Optimization Tool (Base64 Encoding-Safe)
# ==============================================================================

# 1. Авто-скрытие консоли PowerShell ("поварёшки")
$AsyncScript = {
    $code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32Utils" -PassThru
    $hwnd = (Get-Process -Id $PID).MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { $type::ShowWindow($hwnd, 0) }
}
try { &$AsyncScript } catch { }

# Функция безопасного декодирования строк из Base64
function Dec-S([string]$b64) {
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Mutex
$script:AppMutexName = "Global\CleanerDS_SingleInstance_Mutex"
$script:MutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, $script:AppMutexName, [ref]$script:MutexCreated)

if (-not $script:MutexCreated) {
    [System.Windows.Forms.MessageBox]::Show((Dec-S "0J/RgNC40LvQvtC20LXQvdC40LUgQ2xlYW5lckRTINGD0LbQtSDQt9Cw0L/Rg9GJ0LXQvdC4IQ=="), "CleanerDS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
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
        Write-Log -Message (Dec-S "0JfQsNCy0LXRgNGI0LXQvdC40LUg0L/RgNC%2B0YbQtdGB0YHQvtCyIERpc2NvcmQuLi4=") -Level "WARN"
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
            Write-Log -Message (Dec-S "RGlzY29yZCDQt9Cw0L/Rg9GJ0LXQvS4=") -Level "SUCCESS"
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
    Write-Log -Message "$((Dec-S '0KDQtdC30LXRgNCy0L3QsNGPINC60L7Qv9C40Y8g0YHQvtC30LTQsNC90LA6')) $timestamp" -Level "SUCCESS"
    if ($ShowDialogs) { [System.Windows.Forms.MessageBox]::Show((Dec-S "0KDQtdC30LXRgNCy0L3QsNGPINC60L7Qv9C40Y8g0YHQv9C10YjQvdC%2BINGB0L7Qt9C00LDQvdCwIQ=="), (Dec-S "0KPRgdC/0LXRhQ=="), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) }
    Update-Status
    Update-ProgressBar -Value 0
    return $true
}

function Start-CleaningProcess {
    if (-not $script:ChkLocales.Checked -and -not $script:ChkModules.Checked -and -not $script:ChkCache.Checked) {
        [System.Windows.Forms.MessageBox]::Show((Dec-S "0JLRi9Cx0LXRgNC40YLQtSDRjdC70LXQvNC10L3RgtGLIQ=="), (Dec-S "0J/RgNC10LTRg9C/0YDQtdC20LTQtdC90LjQtQ=="), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
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
                Write-Log -Message (Dec-S "0K/Qt9GL0LrQvtCy0YvQtSDRgtCw0LHQu9C40YbRsyDQvtC30LjRidC10L3Riy4=") -Level "INFO"
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
                    if (-not $keep) { Remove-Item -Path $mod.FullName -Recurse -Force; Write-Log -Message "$((Dec-S '0KPQtNCw0LvRkdC9INC80L7QtNGD0LvRjDogaQ==')) $($mod.Name)" -Level "INFO" }
                }
            }
        }
    }
    Update-ProgressBar -Value 80

    if ($script:ChkCache.Checked) {
        @($script:CachePath, $script:CodeCachePath, $script:GPUCachePath) | ForEach-Object {
            if (Test-Path -Path $_) { Get-ChildItem -Path $_ -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-Log -Message (Dec-S "0JrRjdC4INC4INC00LDQvdC90YvQtSDQvtC30LjRidC10L3Riy4=") -Level "INFO"
    }

    Update-ProgressBar -Value 100
    Write-Log -Message (Dec-S "0J7Qv9GC0LjQvNC40LfQsNGG0LjRjyDQt9Cw0LLQtdGA0YjQtdC90LAh") -Level "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show((Dec-S "RGlzY29yZCDRg9GB0L/QtdGI0L3QviDQvtC/0YLQuNC80LjQt9C40YDQvtCy0LDQvCE="), (Dec-S "0KPRgdC/0LXRhQ=="), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Update-Status
    Update-ProgressBar -Value 0
}

function Update-Status {
    $process = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    $script:LblStatusDiscord.Text = if ($process) { (Dec-S "0JfQsNC/0YPRidC10L0=") } else { (Dec-S "0J7RgdGC0LDQvdC%2B0LLQu9C10L0=") }
    $script:LblStatusDiscord.ForeColor = if ($process) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Gray }

    $appFolder = Find-Discord
    $script:LblVersion.Text = if ($appFolder) { (Split-Path -Path $appFolder -Leaf) -replace "app-", "" } else { (Dec-S "0J3QtSDQvdCw0LnQtNC10L0=") }
}

function Show-WhyInfo {
    param([string]$Title, [string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# --- GUI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "CleanerDS — Discord Optimization Tool"
$form.Size = New-Object System.Drawing.Size(900, 680)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(54, 57, 63)
$form.ForeColor = [System.Drawing.Color]::White

$panelHeader = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 70); Dock = "Top"; BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37) }
$lblTitle = New-Object System.Windows.Forms.Label -Property @{ Text = "ClientRDS"; Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold); ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242); AutoSize = $true; Location = New-Object System.Drawing.Point(20, 15) }
$panelHeader.Controls.Add($lblTitle)

$panelStatus = New-Object System.Windows.Forms.Panel -Property @{ Size = New-Object System.Drawing.Size(900, 45); Location = New-Object System.Drawing.Point(0, 70); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }
$script:LblStatusDiscord = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(145, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$script:LblVersion = New-Object System.Windows.Forms.Label -Property @{ Text = "..."; Location = New-Object System.Drawing.Point(345, 12); AutoSize = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$panelStatus.Controls.AddRange(@(
    (New-Object System.Windows.Forms.Label -Property @{ Text = (Dec-S "0KHRgtCw0YLRg9GBIERpc2NvcmQ6"); Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(20, 12); AutoSize = $true }),
    $script:LblStatusDiscord,
    (New-Object System.Windows.Forms.Label -Property @{ Text = (Dec-S "0JLQtdGA0YHQuNGFOg=="); Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold); Location = New-Object System.Drawing.Point(270, 12); AutoSize = $true }),
    $script:LblVersion
))

$panelOptions = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(20, 125); Size = New-Object System.Drawing.Size(620, 110); BackColor = [System.Drawing.Color]::FromArgb(47, 49, 54) }

$script:ChkLocales = New-Object System.Windows.Forms.CheckBox -Property @{ Text = (Dec-S "0KPQtNCw0LvQuNGC0Ywg0L3QtdC40YHQv9C%2B0LvRjNC30YPQtdC80YvQtSDRj9C30YvQutC4IChsb2NhbGVzKQ=="); Location = New-Object System.Drawing.Point(15, 12); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyLoc = New-Object System.Windows.Forms.Button -Property @{ Text = (Dec-S "0JfQsNGH0LXQvD8="); Location = New-Object System.Drawing.Point(510, 10); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyLoc.FlatAppearance.BorderSize = 0
$btnWhyLoc.Add_Click({ Show-WhyInfo -Title (Dec-S "0JfQsNGH0LXQvCDRj9C30YvQutC4Pw==") -Message (Dec-S "0KPQtNCw0LvRj9C10YIgNzArINC70LjRgtC90LjRhSANC30YvQutC%2B0LIgQ2hyb21pdW0sINGD0YHQutC%2B0YDRj9C3INC30LDQv9GD0YHQui4=") })

$script:ChkModules = New-Object System.Windows.Forms.CheckBox -Property @{ Text = (Dec-S "0JLRi9GA0LXQt9Cw0YLRjCDQvdC10L3Rg9C20L3RgtC1INC80L%2BQtNGD0LvQuCAobW9kdWxlcyk="); Location = New-Object System.Drawing.Point(15, 42); Size = New-Object System.Drawing.Size(350, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyMod = New-Object System.Windows.Forms.Button -Property @{ Text = (Dec-S "0JfQsNGH0LXQvD8="); Location = New-Object System.Drawing.Point(510, 40); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyMod.FlatAppearance.BorderSize = 0
$btnWhyMod.Add_Click({ Show-WhyInfo -Title (Dec-S "0JfQsNGH0LXQvCDQvNC%2B0LTRg9C70Lg/=") -Message (Dec-S "0JLRi9GA0LXQt9Cw0YLRjCDQvtCy0LXRgNC70LXQuSDQuCDRgtC10LvQtdC80LXRgtGA0LjRjtC3INC%2B0YHRgtCw0LLQu9C30Y8g0LfQstGD0Log0LggS3Jpc3Au") })

$script:ChkCache = New-Object System.Windows.Forms.CheckBox -Property @{ Text = (Dec-S "0J7Rh9C40YHRgtC40YLRjCDQutGN0YgsIENvZGVDYWNoZSDQuCBUZW1w"); Location = New-Object System.Drawing.Point(15, 72); Size = New-Object System.Drawing.Size(380, 25); Checked = $true; Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }
$btnWhyCache = New-Object System.Windows.Forms.Button -Property @{ Text = (Dec-S "0JfQsNGH0LXQvD8="); Location = New-Object System.Drawing.Point(510, 70); Size = New-Object System.Drawing.Size(95, 26); BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242); FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
$btnWhyCache.FlatAppearance.BorderSize = 0
$btnWhyCache.Add_Click({ Show-WhyInfo -Title (Dec-S "0JfQsNGH0LXQvCDQutGN0Yg/=") -Message (Dec-S "0KPQtNCw0LvRj9C10YIg0YHRgNC%2B0LzQv9C40LvQuNGA0L7QstCw0L3QvdGL0LUg0YHQutGA0LjQv9GC0Ysg0Lgg0LrRjdGI0LjRgNC%2B0LLQsNC90L3RgtC1INC80LXQtNC40LAu") })

$panelOptions.Controls.AddRange(@($script:ChkLocales, $btnWhyLoc, $script:ChkModules, $btnWhyMod, $script:ChkCache, $btnWhyCache))

$script:RichTextBoxLog = New-Object System.Windows.Forms.RichTextBox -Property @{ Location = New-Object System.Drawing.Point(20, 245); Size = New-Object System.Drawing.Size(620, 355); BackColor = [System.Drawing.Color]::FromArgb(32, 34, 37); ForeColor = [System.Drawing.Color]::Gainsboro; Font = New-Object System.Drawing.Font("Consolas", 9.5); ReadOnly = $true; BorderStyle = "None" }

$panelButtons = New-Object System.Windows.Forms.Panel -Property @{ Location = New-Object System.Drawing.Point(660, 125); Size = New-Object System.Drawing.Size(200, 475) }

function Make-Btn([string]$text, [int]$y, $action, $color = [System.Drawing.Color]::FromArgb(79, 84, 92)) {
    $b = New-Object System.Windows.Forms.Button -Property @{ Text = $text; Location = New-Object System.Drawing.Point(0, $y); Size = New-Object System.Drawing.Size(200, 42); BackColor = $color; ForeColor = "White"; FlatStyle = "Flat"; Cursor = [System.Windows.Forms.Cursors]::Hand }
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $b.Add_Click($action)
    return $b
}

$panelButtons.Controls.AddRange(@(
    (Make-Btn (Dec-S "0KHQvtC30LTQsNGC0YwgQmFja3Vw") 0 { Create-Backup }),
    (Make-Btn (Dec-S "0J7Rh9C40YHRgtC40YLRjCBEaXNjb3Jk") 52 { Start-CleaningProcess } ([System.Drawing.Color]::FromArgb(237, 66, 69))),
    (Make-Btn (Dec-S "0JfQsNC/0YPRgdGC0LjRgtGMINAEaXNjb3Jk") 104 { Start-Discord } ([System.Drawing.Color]::FromArgb(57, 105, 54))),
    (Make-Btn (Dec-S "0JLRi9GF0L7QtA==") 425 { $form.Close() })
))

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = New-Object System.Drawing.Point(0, 615); Size = New-Object System.Drawing.Size(900, 10); Dock = "Bottom" }

$form.Controls.AddRange(@($panelHeader, $panelStatus, $panelOptions, $script:RichTextBoxLog, $panelButtons, $script:ProgressBar))
$form.Add_Shown({ Write-Log -Message (Dec-S "Q2xlYW5lckRTINCz0L7RgtC%2B0LIg0Log0YDQsNCx0L7RgtC1Lg==") -Level "SUCCESS"; Update-Status })
$form.Add_FormClosing({ if ($null -ne $script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
