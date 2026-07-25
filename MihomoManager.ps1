#Requires -Version 5.1
# Mihomo 图形管理面板
# 请通过「Mihomo管理.vbs」双击打开（无黑框）

# 不用 StrictMode：单个进程对象没有 .Count，严格模式会直接崩
# GUI 程序用 Continue，避免状态刷新里的小错误直接炸掉窗口
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 高分屏字体清晰：开启 DPI 感知，避免被系统“放大拉伸”导致发糊
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MihomoDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
}
'@ -ErrorAction Stop

    $ok = $false
    try {
        # 2 = PROCESS_PER_MONITOR_DPI_AWARE
        $hr = [MihomoDpi]::SetProcessDpiAwareness(2)
        if ($hr -eq 0) { $ok = $true }
    } catch {}
    if (-not $ok) {
        try { [void][MihomoDpi]::SetProcessDPIAware() } catch {}
    }
} catch {
    # 类型注入失败时忽略，继续用系统默认缩放
}

[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    # 必须在创建任何控件之前调用；GDI+ 文本渲染通常比 GDI 更清晰
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
} catch {}

# 统一 UI 字体（微软雅黑 UI，略大于默认，高分屏更易读）
function New-UiFont {
    param(
        [double]$Size = 10,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    $candidates = @(
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Segoe UI',
        'Tahoma'
    )
    foreach ($name in $candidates) {
        try {
            return New-Object System.Drawing.Font($name, [float]$Size, $Style, [System.Drawing.GraphicsUnit]::Point)
        } catch {}
    }
    return New-Object System.Drawing.Font([System.Drawing.SystemFonts]::MessageBoxFont.FontFamily, [float]$Size, $Style)
}

# -------------------- 路径与常量 --------------------
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location -LiteralPath $Root

$ExePath      = Join-Path $Root 'mihomo.exe'
$ConfigPath   = Join-Path $Root 'config.yaml'
$StartVbsPath = Join-Path $Root 'start-mihomo.vbs'
$StartupDir   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$StartupLnk   = Join-Path $StartupDir 'Mihomo.lnk'
$ProxyRegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

# 配置在线更新地址（可选；没有可先留空，按钮会提示）
$GistUrl = 'https://gist.githubusercontent.com/yg8335266/847e4a81338c85bac1a6783666d3249e/raw/myrule.yaml'

# 内核上游（MetaCubeX/mihomo 官方 Release）
$MihomoRepo = 'MetaCubeX/mihomo'
# windows-amd64 压缩包名匹配（可按需要改 arm64）
$MihomoAssetPattern = 'windows-amd64'

# -------------------- 工具函数 --------------------
function Write-UiLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = '[{0}][{1}] {2}' -f $ts, $Level, $Message
    try {
        if ($null -ne $script:txtLog -and -not $script:txtLog.IsDisposed) {
            $script:txtLog.AppendText($line + [Environment]::NewLine)
            $script:txtLog.SelectionStart = $script:txtLog.TextLength
            $script:txtLog.ScrollToCaret()
        }
    } catch {
        # 界面尚未就绪时忽略
    }
}

function Get-MixedPort {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
        $t = $line.Trim()
        if ($t.StartsWith('#')) { continue }
        if ($t -match '^mixed-port\s*:\s*(\d+)') {
            return [int]$Matches[1]
        }
    }
    return $null
}

function Get-ExternalController {
    # 只从 config.yaml 读取 external-controller，不写死默认端口
    $hostPort = $null
    $secret = ''
    $uiName = ''

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return [pscustomobject]@{
            HostPort = $null
            Secret   = ''
            UiName   = ''
            BaseUrl  = $null
            UiUrl    = $null
            Ok       = $false
            Error    = "未找到配置文件: $ConfigPath"
        }
    }

    foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
        $t = $line.Trim()
        if ($t.StartsWith('#')) { continue }
        if ($t -match '^external-controller\s*:\s*(.+)$') {
            $hostPort = $Matches[1].Trim().Trim('"').Trim("'")
        }
        elseif ($t -match '^secret\s*:\s*(.+)$') {
            $secret = $Matches[1].Trim().Trim('"').Trim("'")
        }
        elseif ($t -match '^external-ui-name\s*:\s*(.+)$') {
            $uiName = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }

    if ([string]::IsNullOrWhiteSpace($hostPort)) {
        return [pscustomobject]@{
            HostPort = $null
            Secret   = $secret
            UiName   = $uiName
            BaseUrl  = $null
            UiUrl    = $null
            Ok       = $false
            Error    = 'config.yaml 中未找到 external-controller'
        }
    }

    # 面板页面路径：有 external-ui-name 时是 /ui/<name>/ ，否则 /ui/
    if ($uiName) {
        $uiUrl = "http://$hostPort/ui/$uiName/"
    } else {
        $uiUrl = "http://$hostPort/ui/"
    }

    return [pscustomobject]@{
        HostPort = $hostPort
        Secret   = $secret
        UiName   = $uiName
        BaseUrl  = "http://$hostPort"
        UiUrl    = $uiUrl
        Ok       = $true
        Error    = $null
    }
}

function Test-ConfigFileLocal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "未找到 mihomo.exe，无法做本地校验。`n路径: $ExePath"
    }
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        throw "待校验配置不存在: $ConfigFile"
    }

    Write-UiLog '正在本地校验配置（mihomo -t，不会上传）…'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    # -t: 仅测试配置；-d: 用当前便携目录解析相对路径；-f: 指定待测配置
    $psi.Arguments = '-t -d "{0}" -f "{1}"' -f $Root, $ConfigFile
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if (-not $proc.WaitForExit(60000)) {
        try { $proc.Kill() } catch {}
        throw '配置校验超时（超过 60 秒）'
    }

    $output = (($stdout + "`n" + $stderr) -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) -join "`n"
    if ($proc.ExitCode -ne 0) {
        if ($output) {
            foreach ($line in ($output -split "`n")) {
                Write-UiLog $line.Trim() 'ERR'
            }
        }
        throw "本地校验失败，未覆盖现有配置。`n详情见上方日志。"
    }

    Write-UiLog '本地校验通过' 'OK'
    if ($output) {
        $brief = ($output -split "`n" | Select-Object -First 3) -join ' | '
        if ($brief) { Write-UiLog $brief }
    }
    return $true
}

function Invoke-ConfigHotReload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )

    $ctrl = Get-ExternalController
    if (-not $ctrl.Ok -or -not $ctrl.BaseUrl) {
        Write-UiLog ('无法热重载：{0}' -f $(if ($ctrl.Error) { $ctrl.Error } else { '未读到 external-controller' })) 'WARN'
        return $false
    }
    $url = '{0}/configs?force=true' -f $ctrl.BaseUrl

    # 先解析成绝对路径；Mihomo 要求 path 必须在“家目录”内
    $abs = $ConfigFile
    try {
        if (Test-Path -LiteralPath $ConfigFile) {
            $abs = (Resolve-Path -LiteralPath $ConfigFile).Path
        }
    } catch {}

    $headers = @{
        'Content-Type' = 'application/json'
    }
    if ($ctrl.Secret) {
        $headers['Authorization'] = 'Bearer {0}' -f $ctrl.Secret
    }

    # 候选请求体（优先明确路径，避免空 path 仍指向旧家目录配置）
    $bodies = @(
        ('{{"path":"{0}"}}' -f ($abs -replace '\\', '/')),
        ('{{"path":"{0}"}}' -f ($abs -replace '\\', '\\\\')),
        '{"path":"config.yaml"}',
        '{"path":""}'
    )

    Write-UiLog ('尝试 API 热重载: {0}' -f $url)

    $lastErr = ''
    foreach ($body in $bodies) {
        try {
            Invoke-RestMethod -Method Put -Uri $url -Headers $headers -Body $body -TimeoutSec 15 | Out-Null
            Write-UiLog 'API 热重载成功，新配置已生效' 'OK'
            return $true
        } catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $msg = $_.ErrorDetails.Message
            }
            # 尝试读响应正文
            try {
                if ($_.Exception.Response) {
                    $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $respText = $sr.ReadToEnd()
                    if ($respText) { $msg = $respText }
                }
            } catch {}
            $lastErr = $msg
            Write-UiLog ('热重载尝试未成功: {0}' -f $msg) 'WARN'
        }
    }

    if ($lastErr -match 'SAFE_PATHS|home directory|subpath|Unauthorized|401') {
        Write-UiLog '当前 Mihomo 可能还在用用户目录家目录（.config\mihomo），或未用本目录启动。' 'WARN'
        Write-UiLog '请先在本面板点「重启」，让进程带 -d 便携目录启动，之后热重载才会稳定。' 'WARN'
    }

    Write-UiLog ('API 热重载失败: {0}' -f $lastErr) 'WARN'
    return $false
}

function Test-MihomoRunning {
    return $null -ne (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue)
}

function Get-MihomoProcesses {
    # 强制数组：0 个 / 1 个 / 多个 都一样好处理
    return @(Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue)
}

function Get-SystemProxyState {
    try {
        $enable = (Get-ItemProperty -Path $ProxyRegPath -Name ProxyEnable -ErrorAction Stop).ProxyEnable
        $server = ''
        try {
            $server = (Get-ItemProperty -Path $ProxyRegPath -Name ProxyServer -ErrorAction Stop).ProxyServer
        } catch {}
        return [pscustomobject]@{
            Enabled = [bool]$enable
            Server  = [string]$server
        }
    } catch {
        return [pscustomobject]@{ Enabled = $false; Server = '' }
    }
}

function Test-AutostartEnabled {
    return (Test-Path -LiteralPath $StartupLnk)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
    param(
        [string]$Text,
        [string]$Title = '请确认'
    )
    $r = [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Show-Info {
    param(
        [string]$Text,
        [string]$Title = '提示'
    )
    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Show-ErrorBox {
    param(
        [string]$Text,
        [string]$Title = '错误'
    )
    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Assert-CoreFiles {
    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "未找到 mihomo.exe`n路径: $ExePath"
    }
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "未找到 config.yaml`n路径: $ConfigPath"
    }
}

function Invoke-ElevatedTaskKill {
    param([string[]]$ArgumentList)

    # 用提权的 taskkill 结束管理员权限启动的 mihomo（会弹 UAC）
    $argLine = ($ArgumentList -join ' ')
    Write-UiLog ('普通权限无法结束进程，尝试提权停止（可能弹出 UAC）…') 'WARN'
    try {
        $p = Start-Process -FilePath 'taskkill.exe' -ArgumentList $ArgumentList -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return ($p.ExitCode -eq 0 -or $p.ExitCode -eq 128)
    } catch {
        # 用户点了 UAC「否」或其他失败
        Write-UiLog ('提权停止失败: {0}' -f $_.Exception.Message) 'ERR'
        return $false
    }
}

function Stop-MihomoCore {
    $procs = @(Get-MihomoProcesses)
    if (@($procs).Count -eq 0) {
        Write-UiLog 'Mihomo 当前未运行'
        return $false
    }

    foreach ($p in @($procs)) {
        Write-UiLog ("正在停止进程 PID={0}" -f $p.Id)
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
        } catch {
            $null = & taskkill.exe /F /PID $p.Id 2>&1
        }
    }

    Start-Sleep -Milliseconds 800
    if (Test-MihomoRunning) {
        $null = & taskkill.exe /F /IM mihomo.exe 2>&1
        Start-Sleep -Milliseconds 800
    }

    # 仍在运行：多半是管理员进程，普通权限杀不掉 → 自动提权 taskkill
    if (Test-MihomoRunning) {
        $procIds = @(@(Get-MihomoProcesses) | ForEach-Object { $_.Id })
        foreach ($procId in $procIds) {
            [void](Invoke-ElevatedTaskKill -ArgumentList @('/F', '/PID', "$procId"))
        }
        Start-Sleep -Milliseconds 800
    }

    if (Test-MihomoRunning) {
        [void](Invoke-ElevatedTaskKill -ArgumentList @('/F', '/IM', 'mihomo.exe'))
        Start-Sleep -Milliseconds 1000
    }

    if (Test-MihomoRunning) {
        throw "无法停止 mihomo.exe。`n请在 UAC 弹窗点「是」。`n若仍失败，可手动打开任务管理器结束 mihomo.exe，或用管理员打开本面板后再试。"
    }

    Write-UiLog 'Mihomo 已停止' 'OK'
    return $true
}

function Start-MihomoCore {
    param([switch]$Silent)

    Assert-CoreFiles

    if (Test-MihomoRunning) {
        Write-UiLog '检测到已在运行，先停止旧进程…'
        [void](Stop-MihomoCore)
    }

    # 与 start-mihomo.vbs 一致：提权后台启动（TUN 通常需要管理员）
    if (Test-Path -LiteralPath $StartVbsPath) {
        Write-UiLog '通过 start-mihomo.vbs 启动（可能弹出 UAC）…'
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('"{0}"' -f $StartVbsPath) -WorkingDirectory $Root
    } else {
        Write-UiLog '未找到 start-mihomo.vbs，改为直接提权启动…' 'WARN'
        $shell = New-Object -ComObject Shell.Application
        $launchArgs = '-d "{0}" -f "{1}"' -f $Root, $ConfigPath
        [void]$shell.ShellExecute($ExePath, $launchArgs, $Root, 'runas', 0)
    }

    $ok = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-MihomoRunning) {
            $ok = $true
            break
        }
    }

    if (-not $ok) {
        throw '启动后未检测到 mihomo 进程。若 UAC 点了「否」，请重新启动并允许管理员权限。'
    }

    Write-UiLog 'Mihomo 已启动' 'OK'
    if (-not $Silent) {
        $port = Get-MixedPort
        Show-Info ("Mihomo 已启动。`n代理端口: {0}" -f $port)
    }
}

function Enable-SystemProxy {
    $port = Get-MixedPort
    if (-not $port) {
        throw '无法从 config.yaml 读取 mixed-port'
    }
    Set-ItemProperty -Path $ProxyRegPath -Name ProxyEnable -Type DWord -Value 1
    Set-ItemProperty -Path $ProxyRegPath -Name ProxyServer -Type String -Value ('127.0.0.1:{0}' -f $port)
    Write-UiLog ('系统代理已开启: 127.0.0.1:{0}' -f $port) 'OK'
}

function Disable-SystemProxy {
    Set-ItemProperty -Path $ProxyRegPath -Name ProxyEnable -Type DWord -Value 0
    Write-UiLog '系统代理已关闭' 'OK'
}

function Enable-Autostart {
    if (-not (Test-Path -LiteralPath $StartVbsPath)) {
        throw "未找到 start-mihomo.vbs，无法设置开机启动。`n路径: $StartVbsPath"
    }
    if (-not (Test-Path -LiteralPath $StartupDir)) {
        New-Item -ItemType Directory -Path $StartupDir -Force | Out-Null
    }

    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($StartupLnk)
    $sc.TargetPath       = $StartVbsPath
    $sc.WorkingDirectory = $Root
    $sc.WindowStyle      = 7
    $sc.Description      = 'Mihomo 开机静默启动'
    $sc.Save()

    if (-not (Test-Path -LiteralPath $StartupLnk)) {
        throw '创建开机启动快捷方式失败'
    }
    Write-UiLog '开机自启已开启' 'OK'
}

function Disable-Autostart {
    if (Test-Path -LiteralPath $StartupLnk) {
        Remove-Item -LiteralPath $StartupLnk -Force
        Write-UiLog '开机自启已关闭' 'OK'
    } else {
        Write-UiLog '本来就没有开机自启'
    }
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-DownloadUrlWithCacheBust {
    param([string]$Url)
    $sep = if ($Url -match '\?') { '&' } else { '?' }
    return ('{0}{1}t={2}' -f $Url, $sep, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
}

function Update-ConfigFromGist {
    if (-not $GistUrl -or $GistUrl -notmatch '^https?://') {
        throw '更新地址无效，请先在 MihomoManager.ps1 顶部修改 $GistUrl'
    }

    # 这一段关键操作必须失败即停，避免“看起来成功其实没写入”
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    $tmp = Join-Path $Root ('config.download.{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
    $bak = $null
    try {
        $oldHash = Get-FileSha256 -Path $ConfigPath
        $oldSize = if (Test-Path -LiteralPath $ConfigPath) { (Get-Item -LiteralPath $ConfigPath).Length } else { 0 }
        if ($oldHash) {
            Write-UiLog ('当前配置: {0} 字节, SHA256={1}...' -f $oldSize, $oldHash.Substring(0, 12))
        }

        $downloadUrl = Get-DownloadUrlWithCacheBust -Url $GistUrl
        Write-UiLog '正在下载新配置（已防缓存）…'
        Write-UiLog ('下载地址: {0}' -f $downloadUrl)
        $downloaded = $false

        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $curlOut = & curl.exe -L --fail --silent --show-error `
                -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' `
                -o $tmp $downloadUrl 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp).Length -gt 0)) {
                $downloaded = $true
            } else {
                Write-UiLog ('curl 下载异常: {0}' -f (($curlOut | Out-String).Trim())) 'WARN'
            }
        }

        if (-not $downloaded) {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmp -UseBasicParsing -Headers @{
                'Cache-Control' = 'no-cache'
                'Pragma'        = 'no-cache'
            }
        }

        if (-not (Test-Path -LiteralPath $tmp) -or ((Get-Item -LiteralPath $tmp).Length -le 0)) {
            throw '下载失败：没有得到有效文件'
        }

        $newSize = (Get-Item -LiteralPath $tmp).Length
        $newHash = Get-FileSha256 -Path $tmp
        Write-UiLog ('下载完成: {0} 字节, SHA256={1}...' -f $newSize, $newHash.Substring(0, 12))

        $content = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content) -or $content -notmatch 'mixed-port\s*:') {
            throw '下载内容看起来不是有效的 mihomo 配置（缺少 mixed-port）。现有配置未被修改。'
        }

        $sameAsOld = ($oldHash -and $newHash -and ($oldHash -eq $newHash))
        if ($sameAsOld) {
            Write-UiLog '下载内容与当前 config.yaml 完全一致（哈希相同）' 'WARN'
        }

        # 1) 本地正式校验：只在本机跑 mihomo -t，失败则绝不覆盖
        Test-ConfigFileLocal -ConfigFile $tmp

        # 2) 校验通过后再备份并覆盖
        if (Test-Path -LiteralPath $ConfigPath) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $bak = Join-Path $Root ('config-{0}.yaml.bak' -f $stamp)
            Copy-Item -LiteralPath $ConfigPath -Destination $bak -Force -ErrorAction Stop
            Write-UiLog ('已备份当前配置: {0}' -f (Split-Path $bak -Leaf)) 'OK'
        }

        # 用字节级写入，避免复制被占用/权限问题时“假成功”
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        try {
            [System.IO.File]::WriteAllBytes($ConfigPath, $bytes)
        } catch {
            # 若文件被占用，尝试先删再写
            Write-UiLog ('直接写入失败，尝试替换写入: {0}' -f $_.Exception.Message) 'WARN'
            $swap = Join-Path $Root ('config.swap.{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
            [System.IO.File]::WriteAllBytes($swap, $bytes)
            Move-Item -LiteralPath $swap -Destination $ConfigPath -Force -ErrorAction Stop
        }

        # 3) 回读确认磁盘上的文件真的变了
        Start-Sleep -Milliseconds 200
        $finalHash = Get-FileSha256 -Path $ConfigPath
        $finalSize = (Get-Item -LiteralPath $ConfigPath).Length
        if (-not $finalHash -or $finalHash -ne $newHash) {
            throw ("写入后校验失败：磁盘上的 config.yaml 与下载内容不一致。`n下载={0}... 磁盘={1}...`n现有配置可能未被成功覆盖。" -f $newHash.Substring(0,12), $(if($finalHash){$finalHash.Substring(0,12)}else{'null'}))
        }
        Write-UiLog ('磁盘确认写入成功: {0} 字节, SHA256={1}...' -f $finalSize, $finalHash.Substring(0, 12)) 'OK'

        if ($sameAsOld) {
            Write-UiLog '注意：远程配置和本地原本就一样，所以看起来像“没更新”' 'WARN'
            Show-Info "下载/校验/写入都成功，但远程配置与本地完全相同。`n所以内容看起来没有变化。`n`n若你刚改了 Gist，可能是缓存或还没保存到 raw 地址。"
        } else {
            Write-UiLog '配置文件已更新（内容已变化，且通过本地校验）' 'OK'
        }

        # 4) 若服务在跑：优先 API 热重载；失败再询问是否重启
        if (Test-MihomoRunning) {
            $reloaded = Invoke-ConfigHotReload -ConfigFile $ConfigPath
            if ($reloaded) {
                if ($sameAsOld) {
                    Show-Info "文件已写入且热重载完成。`n但远程配置与更新前相同，面板内容可能看不出变化。"
                } else {
                    Show-Info "配置已更新并完成热重载。`n新配置已生效（无需重启）。`n若面板仍像旧的，请强制刷新浏览器页面。"
                }
            } else {
                if (Confirm-Action "热重载失败。`n是否重启 Mihomo 使新配置生效？") {
                    Start-MihomoCore -Silent
                    Write-UiLog '已重启以加载新配置' 'OK'
                    Show-Info '配置已更新，Mihomo 已重启。'
                } else {
                    Write-UiLog '未重启：新配置将在下次启动后生效' 'WARN'
                    Show-Info "配置文件已更新，但尚未生效。`n下次启动或手动重启后生效。"
                }
            }
        } else {
            if ($sameAsOld) {
                Show-Info "写入成功，但远程配置与本地原本相同。`n当前 Mihomo 未运行。"
            } else {
                Show-Info "配置已更新（本地校验通过）。`n当前 Mihomo 未运行，下次启动时会使用新配置。"
            }
        }
    } finally {
        $ErrorActionPreference = $prevEap
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem -LiteralPath $Root -Filter 'config.swap.*.tmp' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-FirstSetup {
    Assert-CoreFiles
    $port = Get-MixedPort
    if (-not $port) {
        throw '无法从 config.yaml 读取 mixed-port'
    }

    Write-UiLog ('检测到代理端口: {0}' -f $port)

    try {
        $conns = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Where-Object { $_ })
        foreach ($c in $conns) {
            if ($null -eq $c) { continue }
            $op = $c.OwningProcess
            if ($op -and $op -ne 0) {
                $pnObj = Get-Process -Id $op -ErrorAction SilentlyContinue
                $pn = if ($pnObj) { $pnObj.ProcessName } else { $null }
                if ($pn -and $pn -ne 'mihomo') {
                    Write-UiLog ('端口 {0} 被 {1}(PID {2}) 占用，尝试结束…' -f $port, $pn, $op) 'WARN'
                    Stop-Process -Id $op -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {
        # 旧系统可能没有 Get-NetTCPConnection
    }

    Start-MihomoCore -Silent
    Enable-SystemProxy
    Write-UiLog '首次安装流程完成：服务已启动并已开启系统代理' 'OK'

    $ctrlInfo = Get-ExternalController
    $uiText = if ($ctrlInfo.Ok -and $ctrlInfo.UiUrl) { $ctrlInfo.UiUrl } else { '（配置中未找到 external-controller）' }
    Show-Info ("首次安装完成！`n`n代理: 127.0.0.1:{0}`n面板: {1}`n`n以后日常可直接用本窗口操作。" -f $port, $uiText)
}

function Open-Dashboard {
    $info = Get-ExternalController
    if (-not $info.Ok -or -not $info.UiUrl) {
        throw $(if ($info.Error) { $info.Error } else { '无法从 config.yaml 读取控制面板地址（external-controller）' })
    }
    Write-UiLog ('打开面板: {0}' -f $info.UiUrl)
    Start-Process $info.UiUrl
}

function Get-LocalMihomoVersion {
    if (-not (Test-Path -LiteralPath $ExePath)) { return $null }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath
        $psi.Arguments = '-v'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        [void]$p.WaitForExit(5000)
        $text = ($out + ' ' + $err).Trim()
        if ($text) { return ($text -split "`r?`n")[0].Trim() }
    } catch {}
    return $null
}

function Update-MihomoCoreFromUpstream {
    # 从 GitHub 上游 MetaCubeX/mihomo 的 Release 拉取最新 windows-amd64 内核
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $work = Join-Path $Root ('core-update-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work 'mihomo.zip'
    $extractDir = Join-Path $work 'extract'

    try {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        $localVer = Get-LocalMihomoVersion
        if ($localVer) {
            Write-UiLog ('当前内核: {0}' -f $localVer)
        } else {
            Write-UiLog '当前目录还没有可用的 mihomo.exe（将全新下载）' 'WARN'
        }

        $api = 'https://api.github.com/repos/{0}/releases/latest' -f $MihomoRepo
        Write-UiLog ('查询上游最新版: {0}' -f $api)

        $headers = @{
            'User-Agent' = 'MihomoManager'
            'Accept'     = 'application/vnd.github+json'
        }
        $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 30
        $tag = [string]$release.tag_name
        if (-not $tag) { throw '无法解析上游版本号' }
        Write-UiLog ('上游最新版本: {0}' -f $tag) 'OK'

        $asset = @($release.assets) | Where-Object {
            $_.name -match [regex]::Escape($MihomoAssetPattern) -and $_.name -match '\.zip$' -and $_.name -notmatch 'go120|compatible'
        } | Select-Object -First 1

        if (-not $asset) {
            # 放宽：只要 windows-amd64 zip
            $asset = @($release.assets) | Where-Object {
                $_.name -match 'windows-amd64' -and $_.name -match '\.zip$'
            } | Select-Object -First 1
        }
        if (-not $asset) {
            throw ('未在 Release 中找到匹配资源（需要含 {0} 的 zip）' -f $MihomoAssetPattern)
        }

        Write-UiLog ('下载: {0} ({1:N0} 字节)' -f $asset.name, [int64]$asset.size)
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $curlOut = & curl.exe -L --fail --silent --show-error -o $zipPath $asset.browser_download_url 2>&1
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
                throw ('curl 下载失败: {0}' -f (($curlOut | Out-String).Trim()))
            }
        } else {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
        }

        Write-UiLog '正在解压…'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

        $newExe = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter 'mihomo*.exe' |
            Sort-Object Length -Descending |
            Select-Object -First 1
        if (-not $newExe) {
            throw '压缩包中未找到 mihomo*.exe'
        }
        Write-UiLog ('解压得到: {0}' -f $newExe.Name)

        $wasRunning = Test-MihomoRunning
        if ($wasRunning) {
            Write-UiLog '更新前先停止当前 Mihomo…'
            [void](Stop-MihomoCore)
        }

        # 备份旧内核
        if (Test-Path -LiteralPath $ExePath) {
            $bakDir = Join-Path $Root 'meta-backup'
            New-Item -ItemType Directory -Path $bakDir -Force | Out-Null
            $bakName = 'mihomo-{0}.exe.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
            $bakPath = Join-Path $bakDir $bakName
            Copy-Item -LiteralPath $ExePath -Destination $bakPath -Force
            Write-UiLog ('旧内核已备份: meta-backup\{0}' -f $bakName) 'OK'
        }

        Copy-Item -LiteralPath $newExe.FullName -Destination $ExePath -Force
        $newVer = Get-LocalMihomoVersion
        if ($newVer) {
            Write-UiLog ('内核已更新: {0}' -f $newVer) 'OK'
        } else {
            Write-UiLog '内核文件已替换（未能读取版本号）' 'OK'
        }

        if ($wasRunning) {
            if (Confirm-Action "内核已更新。`n是否立即启动 Mihomo？") {
                Start-MihomoCore -Silent
                Show-Info ("内核已更新并已启动。`n版本: {0}" -f $(if ($newVer) { $newVer } else { $tag }))
            } else {
                Show-Info ("内核已更新。`n版本: {0}`n当前未启动。" -f $(if ($newVer) { $newVer } else { $tag }))
            }
        } else {
            Show-Info ("内核已更新。`n版本: {0}`n可点击「启动」。" -f $(if ($newVer) { $newVer } else { $tag }))
        }
    } finally {
        $ErrorActionPreference = $prevEap
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Open-Folder {
    Start-Process explorer.exe $Root
}

function Update-StatusUi {
    try {
        if ($null -eq $script:form -or $script:form.IsDisposed) { return }

        $running = Test-MihomoRunning
        $port    = Get-MixedPort
        $proxy   = Get-SystemProxyState
        $auto    = Test-AutostartEnabled
        $ctrl    = Get-ExternalController
        $procs   = @(Get-MihomoProcesses)
        $count   = @($procs).Count
        $pids    = if ($count -gt 0) { (@($procs) | ForEach-Object { $_.Id }) -join ', ' } else { '-' }

        if ($running) {
            $script:lblRun.Text = "运行状态：运行中（PID: $pids）"
            $script:lblRun.ForeColor = [System.Drawing.Color]::ForestGreen
        } else {
            $script:lblRun.Text = '运行状态：未运行'
            $script:lblRun.ForeColor = [System.Drawing.Color]::Firebrick
        }

        if ($port) {
            $script:lblPort.Text = "代理端口：$port（mixed-port）"
        } else {
            $script:lblPort.Text = '代理端口：读取失败'
        }

        if ($proxy -and $proxy.Enabled) {
            $script:lblProxy.Text = "系统代理：已开启（$($proxy.Server)）"
            $script:lblProxy.ForeColor = [System.Drawing.Color]::ForestGreen
        } else {
            $script:lblProxy.Text = '系统代理：已关闭'
            $script:lblProxy.ForeColor = [System.Drawing.Color]::DimGray
        }

        if ($auto) {
            $script:lblAuto.Text = '开机自启：已开启'
            $script:lblAuto.ForeColor = [System.Drawing.Color]::ForestGreen
        } else {
            $script:lblAuto.Text = '开机自启：未开启'
            $script:lblAuto.ForeColor = [System.Drawing.Color]::DimGray
        }

        if ($ctrl -and $ctrl.Ok -and $ctrl.UiUrl) {
            $script:lblPanel.Text = "控制面板：$($ctrl.UiUrl)"
        } else {
            $err = if ($ctrl -and $ctrl.Error) { $ctrl.Error } else { '读取失败' }
            $script:lblPanel.Text = "控制面板：$err"
        }

        if (Test-IsAdmin) {
            $script:lblAdmin.Text = '当前权限：管理员'
        } else {
            $script:lblAdmin.Text = '当前权限：普通用户（启动/停止可能弹出 UAC）'
        }

        $script:lblDir.Text = "目录：$Root"
    } catch {
        # 定时刷新绝不能把窗口打崩
    }
}

function Invoke-Safe {
    param([scriptblock]$Action)

    try {
        $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        if ($null -ne $script:actionButtons) {
            foreach ($b in @($script:actionButtons)) {
                if ($null -ne $b) { $b.Enabled = $false }
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
        & $Action
    } catch {
        $msg = $_.Exception.Message
        Write-UiLog $msg 'ERR'
        Show-ErrorBox $msg
    } finally {
        if ($null -ne $script:actionButtons) {
            foreach ($b in @($script:actionButtons)) {
                if ($null -ne $b) { $b.Enabled = $true }
            }
        }
        try { $script:form.Cursor = [System.Windows.Forms.Cursors]::Default } catch {}
        Update-StatusUi
    }
}

# -------------------- 界面 --------------------
$uiFont     = New-UiFont 10
$uiFontBold = New-UiFont 10 ([System.Drawing.FontStyle]::Bold)
$uiFontTitle = New-UiFont 15 ([System.Drawing.FontStyle]::Bold)
$uiFontLog  = New-UiFont 9.5
try {
    $uiFontLog = New-Object System.Drawing.Font('Consolas', 9.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
} catch {
    try {
        $uiFontLog = New-Object System.Drawing.Font('Cascadia Mono', 9.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    } catch {}
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Mihomo 管理面板'
$form.ClientSize = New-Object System.Drawing.Size(720, 890)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.Font = $uiFont
$form.BackColor = [System.Drawing.Color]::White
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)
try { $form.UseCompatibleTextRendering = $false } catch {}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Mihomo 一键管理'
$lblTitle.Font = $uiFontTitle
$lblTitle.Location = New-Object System.Drawing.Point(22, 16)
$lblTitle.AutoSize = $true
try { $lblTitle.UseCompatibleTextRendering = $false } catch {}
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '启动、停止、系统代理、开机自启、更新配置，都在这一个窗口完成'
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Location = New-Object System.Drawing.Point(24, 52)
$lblSub.AutoSize = $true
try { $lblSub.UseCompatibleTextRendering = $false } catch {}
$form.Controls.Add($lblSub)

$grpStatus = New-Object System.Windows.Forms.GroupBox
$grpStatus.Text = '当前状态'
$grpStatus.Location = New-Object System.Drawing.Point(20, 86)
$grpStatus.Size = New-Object System.Drawing.Size(680, 210)
$form.Controls.Add($grpStatus)

# 行高/行距加大，避免中文底部被下一行挡住
$statusLabelWidth = 640
$statusLabelHeight = 28
$statusLineStep = 34
$statusStartY = 32

$script:lblRun = New-Object System.Windows.Forms.Label
$script:lblRun.Location = New-Object System.Drawing.Point(18, $statusStartY)
$script:lblRun.Size = New-Object System.Drawing.Size($statusLabelWidth, $statusLabelHeight)
$script:lblRun.Font = $uiFontBold
$script:lblRun.AutoEllipsis = $true
try { $script:lblRun.UseCompatibleTextRendering = $false } catch {}
$grpStatus.Controls.Add($script:lblRun)

$script:lblPort = New-Object System.Windows.Forms.Label
$script:lblPort.Location = New-Object System.Drawing.Point(18, ($statusStartY + $statusLineStep))
$script:lblPort.Size = New-Object System.Drawing.Size($statusLabelWidth, $statusLabelHeight)
$script:lblPort.AutoEllipsis = $true
try { $script:lblPort.UseCompatibleTextRendering = $false } catch {}
$grpStatus.Controls.Add($script:lblPort)

$script:lblProxy = New-Object System.Windows.Forms.Label
$script:lblProxy.Location = New-Object System.Drawing.Point(18, ($statusStartY + $statusLineStep * 2))
$script:lblProxy.Size = New-Object System.Drawing.Size($statusLabelWidth, $statusLabelHeight)
$script:lblProxy.AutoEllipsis = $true
try { $script:lblProxy.UseCompatibleTextRendering = $false } catch {}
$grpStatus.Controls.Add($script:lblProxy)

$script:lblAuto = New-Object System.Windows.Forms.Label
$script:lblAuto.Location = New-Object System.Drawing.Point(18, ($statusStartY + $statusLineStep * 3))
$script:lblAuto.Size = New-Object System.Drawing.Size($statusLabelWidth, $statusLabelHeight)
$script:lblAuto.AutoEllipsis = $true
try { $script:lblAuto.UseCompatibleTextRendering = $false } catch {}
$grpStatus.Controls.Add($script:lblAuto)

$script:lblPanel = New-Object System.Windows.Forms.Label
$script:lblPanel.Location = New-Object System.Drawing.Point(18, ($statusStartY + $statusLineStep * 4))
$script:lblPanel.Size = New-Object System.Drawing.Size($statusLabelWidth, $statusLabelHeight)
$script:lblPanel.AutoEllipsis = $true
try { $script:lblPanel.UseCompatibleTextRendering = $false } catch {}
$grpStatus.Controls.Add($script:lblPanel)

$grpActions = New-Object System.Windows.Forms.GroupBox
$grpActions.Text = '常用操作'
$grpActions.Location = New-Object System.Drawing.Point(20, 310)
$grpActions.Size = New-Object System.Drawing.Size(680, 250)
$form.Controls.Add($grpActions)

function New-ActionButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 150,
        [int]$H = 42
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.Font = $uiFont
    $b.FlatStyle = 'System'
    $b.UseCompatibleTextRendering = $false
    $grpActions.Controls.Add($b)
    return $b
}

$btnStart    = New-ActionButton '启动' 20 30
$btnStop     = New-ActionButton '停止' 185 30
$btnRestart  = New-ActionButton '重启' 350 30
$btnRefresh  = New-ActionButton '刷新状态' 515 30
$btnProxyOn  = New-ActionButton '开启系统代理' 20 84
$btnProxyOff = New-ActionButton '关闭系统代理' 185 84
$btnAutoOn   = New-ActionButton '开启开机自启' 350 84
$btnAutoOff  = New-ActionButton '关闭开机自启' 515 84
$btnUpdate   = New-ActionButton '更新配置' 20 138
$btnCore     = New-ActionButton '更新内核' 185 138
$btnDash     = New-ActionButton '打开面板' 350 138
$btnFolder   = New-ActionButton '打开目录' 515 138
$btnSetup    = New-ActionButton '首次安装' 20 192
$btnExample  = New-ActionButton '生成示例配置' 185 192

$script:actionButtons = @(
    $btnStart, $btnStop, $btnRestart, $btnRefresh,
    $btnProxyOn, $btnProxyOff, $btnAutoOn, $btnAutoOff,
    $btnUpdate, $btnCore, $btnDash, $btnFolder,
    $btnSetup, $btnExample
)

# 日志框
$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = '运行日志'
$grpLog.Location = New-Object System.Drawing.Point(20, 574)
$grpLog.Size = New-Object System.Drawing.Size(680, 200)
$form.Controls.Add($grpLog)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.ReadOnly = $true
$script:txtLog.Location = New-Object System.Drawing.Point(14, 28)
$script:txtLog.Size = New-Object System.Drawing.Size(650, 156)
$script:txtLog.BackColor = [System.Drawing.Color]::WhiteSmoke
$script:txtLog.Font = $uiFontLog
$script:txtLog.BorderStyle = 'FixedSingle'
$grpLog.Controls.Add($script:txtLog)

# 底部两行
$script:lblAdmin = New-Object System.Windows.Forms.Label
$script:lblAdmin.Location = New-Object System.Drawing.Point(22, 790)
$script:lblAdmin.Size = New-Object System.Drawing.Size(680, 26)
$script:lblAdmin.ForeColor = [System.Drawing.Color]::DimGray
$script:lblAdmin.AutoEllipsis = $true
try { $script:lblAdmin.UseCompatibleTextRendering = $false } catch {}
$form.Controls.Add($script:lblAdmin)

$script:lblDir = New-Object System.Windows.Forms.Label
$script:lblDir.Location = New-Object System.Drawing.Point(22, 822)
$script:lblDir.Size = New-Object System.Drawing.Size(680, 26)
$script:lblDir.ForeColor = [System.Drawing.Color]::DarkGray
$script:lblDir.AutoEllipsis = $true
try { $script:lblDir.UseCompatibleTextRendering = $false } catch {}
$form.Controls.Add($script:lblDir)

# -------------------- 事件绑定 --------------------
$btnRefresh.Add_Click({
    Update-StatusUi
    Write-UiLog '状态已刷新'
})

$btnStart.Add_Click({
    Invoke-Safe { Start-MihomoCore }
})

$btnStop.Add_Click({
    Invoke-Safe {
        if (-not (Test-MihomoRunning)) {
            Show-Info 'Mihomo 当前未运行。'
            return
        }
        if (Confirm-Action '确定停止 Mihomo？') {
            [void](Stop-MihomoCore)
            $px = Get-SystemProxyState
            if ($px.Enabled -and (Confirm-Action "服务已停止。`n是否同时关闭系统代理？")) {
                Disable-SystemProxy
            }
            Show-Info 'Mihomo 已停止。'
        }
    }
})

$btnRestart.Add_Click({
    Invoke-Safe {
        Write-UiLog '正在重启…'
        if (Test-MihomoRunning) { [void](Stop-MihomoCore) }
        Start-MihomoCore -Silent
        Show-Info 'Mihomo 已重启。'
    }
})

$btnProxyOn.Add_Click({
    Invoke-Safe {
        Enable-SystemProxy
        Show-Info ('系统代理已开启：127.0.0.1:{0}' -f (Get-MixedPort))
    }
})

$btnProxyOff.Add_Click({
    Invoke-Safe {
        Disable-SystemProxy
        Show-Info '系统代理已关闭。'
    }
})

$btnAutoOn.Add_Click({
    Invoke-Safe {
        Enable-Autostart
        Show-Info "开机自启已开启。`n下次开机将自动后台启动 Mihomo。"
    }
})

$btnAutoOff.Add_Click({
    Invoke-Safe {
        Disable-Autostart
        Show-Info '开机自启已关闭。'
    }
})

$btnUpdate.Add_Click({
    Invoke-Safe {
        if ([string]::IsNullOrWhiteSpace($GistUrl)) {
            Show-Info "尚未设置配置更新地址。`n请编辑 MihomoManager.ps1 顶部的 `$GistUrl。"
            return
        }
        $msg = "将从在线地址下载并覆盖本地 config.yaml。`n会先自动备份当前配置，并做本地校验。`n是否继续？`n`n地址：`n$GistUrl"
        if (-not (Confirm-Action $msg)) { return }
        Update-ConfigFromGist
        # Update-ConfigFromGist 内部已有结果提示，这里不再重复弹窗
    }
})

$btnCore.Add_Click({
    Invoke-Safe {
        $msg = "将从 GitHub 上游仓库下载最新 mihomo 内核：`n$MihomoRepo`n`n匹配资源: $MihomoAssetPattern`n会先备份旧 mihomo.exe 到 meta-backup\`n是否继续？"
        if (-not (Confirm-Action $msg '更新内核')) { return }
        Update-MihomoCoreFromUpstream
    }
})

$btnSetup.Add_Click({
    Invoke-Safe {
        $msg = "将执行「首次安装」流程：`n1. 检查文件`n2. 启动 Mihomo`n3. 开启系统代理`n`n是否继续？"
        if (-not (Confirm-Action $msg)) { return }
        Invoke-FirstSetup
    }
})

$btnExample.Add_Click({
    Invoke-Safe {
        $example = Join-Path $Root 'config.example.yaml'
        if (-not (Test-Path -LiteralPath $example)) {
            throw "未找到 config.example.yaml`n路径: $example"
        }
        if (Test-Path -LiteralPath $ConfigPath) {
            if (-not (Confirm-Action "本地已有 config.yaml。`n是否先备份再从示例覆盖？`n（会备份为 config-时间.yaml.bak）")) {
                return
            }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $bak = Join-Path $Root ('config-{0}.yaml.bak' -f $stamp)
            Copy-Item -LiteralPath $ConfigPath -Destination $bak -Force
            Write-UiLog ('已备份: {0}' -f (Split-Path $bak -Leaf)) 'OK'
        }
        Copy-Item -LiteralPath $example -Destination $ConfigPath -Force
        Write-UiLog '已从 config.example.yaml 生成 config.yaml' 'OK'
        Show-Info "已生成 config.yaml。`n请用记事本修改：`n1) secret`n2) 订阅 URL`n3) 端口（如需）`n然后再启动。"
    }
})

$btnDash.Add_Click({
    Invoke-Safe { Open-Dashboard }
})

$btnFolder.Add_Click({
    Invoke-Safe { Open-Folder }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    try { Update-StatusUi } catch {}
})

$form.Add_Shown({
    try {
        Update-StatusUi
        Write-UiLog '管理面板已就绪。'
        $timer.Start()
    } catch {
        Show-ErrorBox $_.Exception.Message
    }
})

$form.Add_FormClosed({
    try {
        $timer.Stop()
        $timer.Dispose()
    } catch {}
})

# -------------------- 启动界面 --------------------
$script:form = $form
[System.Windows.Forms.Application]::Run($form)
