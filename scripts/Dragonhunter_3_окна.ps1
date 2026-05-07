param(
    [string]$ConfigPath = "$PSScriptRoot\dragonhunter-3-windows.config.psd1",
    [switch]$SkipTerminate,
    [switch]$SkipCacheClear,
    [switch]$TerminateAllAtStart,
    [int]$LaunchDelaySec = -1,
    [int]$WaitForGameSec = -1,
    [int]$MaxRetriesPerBox = -1,
    [switch]$MonitorDetached,
    [switch]$RunArrangerAfterLaunch,
    [string]$ArrangerScriptPath = ""
)

$ErrorActionPreference = "SilentlyContinue"

function Get-EmbeddedDefaultConfig {
    return @{
        StartExe                 = "C:\Program Files\Sandboxie-Plus\Start.exe"
        LauncherExe              = "D:\4399\slsmru\launcher\Dragon_hunter.exe"
        Boxes                    = @("1Atarun", "2Emilian", "3Ceres")
        SkipTerminate            = $true
        SkipCacheClear           = $true
        LaunchDelaySec           = 60
        WaitForGameSec           = 900
        StableSec                = 20
        MaxRetriesPerBox         = 1
        WaitStartingTimeoutSec   = 120
        WaitStartingStableSec    = 10
        EnableCdnCheck           = $true
        CfgUrl                     = "https://lyzs-cdnres.4399ru.com/RU/stable/mix_ru/up/pc_exe/cfg.xml"
        CdnMaxAttempts             = 6
        CdnDelaySec                = 10
        DnsWarmupServer            = "9.9.9.9"
        WarmupDomains              = @(
            "lyzs-cdnres.4399ru.com",
            "pc.4399sy.ru",
            "mkts.4399sy.ru",
            "y.4399sy.ru"
        )
        MonitorClosedWindows       = $true
        MonitorPollSec             = 5
        MonitorDownConfirmChecks   = 5
        MonitorToastTitle          = "Dragonhunter Monitor"
        MonitorInBackground        = $false
        RunArrangerAfterLaunch     = $false
        ArrangerScriptPath         = ""
    }
}

function Escape-XmlText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return ($Text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;").Replace("'", "&apos;"))
}

function Get-SandboxCacheBase {
    param(
        [string]$LauncherExePath,
        [string]$BoxName
    )
    $launcherDir = Split-Path -Path $LauncherExePath -Parent
    $slsmruBase = Split-Path -Path $launcherDir -Parent
    if ($slsmruBase.Length -lt 3) { return $null }
    $drivePath = $slsmruBase.Substring(0, 1) + $slsmruBase.Substring(2)
    return "C:\Sandbox\$env:USERNAME\$BoxName\drive\$drivePath"
}

function Get-GameWindowHandle {
    param([string]$Box)

    $game = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -like "pc_lyzs_ru_rel_*" -and
            $_.MainWindowHandle -ne 0 -and
            $_.MainWindowTitle.Contains("[$Box]")
        } |
        Select-Object -First 1

    if ($game) { return $game.MainWindowHandle }
    return [IntPtr]::Zero
}

function Get-LauncherWindowHandle {
    param([string]$Box)

    $launcher = Get-Process -Name "Dragon_hunter" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne 0 -and
            $_.MainWindowTitle.Contains("[$Box]")
        } |
        Select-Object -First 1

    if ($launcher) { return $launcher.MainWindowHandle }
    return [IntPtr]::Zero
}

function Wait-CdnReady {
    param(
        [string]$Url,
        [int]$MaxAttempts,
        [int]$DelaySec
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 15 -UseBasicParsing
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
                Write-Host "CDN check OK (attempt $attempt)." -ForegroundColor DarkGreen
                return $true
            }
        } catch {}

        Write-Host "CDN check failed (attempt $attempt/$MaxAttempts), retry in $DelaySec sec..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $DelaySec
    }

    return $false
}

function Wait-BoxReady {
    param(
        [string]$Box,
        [int]$TimeoutSec,
        [int]$StableSec,
        [int]$PollSec = 5
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $stableSince = $null

    while ((Get-Date) -lt $deadline) {
        $gameHwnd = Get-GameWindowHandle -Box $Box
        $launcherHwnd = Get-LauncherWindowHandle -Box $Box

        if ($gameHwnd -ne [IntPtr]::Zero -and $launcherHwnd -eq [IntPtr]::Zero) {
            if (-not $stableSince) { $stableSince = Get-Date }
            if (((Get-Date) - $stableSince).TotalSeconds -ge $StableSec) {
                return $true
            }
        } else {
            $stableSince = $null
        }

        Start-Sleep -Seconds $PollSec
    }

    return $false
}

function Stop-BoxProcesses {
    param([string]$Box, [string]$StartExePath)

    & $StartExePath "/box:$Box" /terminate | Out-Null
    Start-Sleep -Seconds 2
}

function Get-BoxState {
    param([string]$Box)

    $gameHwnd = Get-GameWindowHandle -Box $Box
    $launcherHwnd = Get-LauncherWindowHandle -Box $Box

    if ($gameHwnd -ne [IntPtr]::Zero -and $launcherHwnd -eq [IntPtr]::Zero) { return "Ready" }
    if ($gameHwnd -ne [IntPtr]::Zero -or $launcherHwnd -ne [IntPtr]::Zero) { return "Starting" }
    return "Down"
}

function Show-WindowsToastNotification {
    param(
        [string]$Title,
        [string]$Message
    )

    $safeTitle = Escape-XmlText -Text $Title
    $safeMessage = Escape-XmlText -Text $Message

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $xml = @"
<toast activationType="foreground">
  <visual>
    <binding template="ToastGeneric">
      <text>$safeTitle</text>
      <text>$safeMessage</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@

        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Windows PowerShell")
        $notifier.Show($toast)
    } catch {
        Write-Host "Toast failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {}
}

function Start-WindowCloseMonitor {
    param(
        [string[]]$Boxes,
        [int]$PollSec,
        [int]$DownConfirmChecks,
        [string]$ToastTitle
    )

    $wasUp = @{}
    $downCount = @{}
    foreach ($box in $Boxes) {
        $wasUp[$box] = (Get-BoxState -Box $box) -ne "Down"
        $downCount[$box] = 0
    }

    Write-Host "Window monitor is running. Press Ctrl+C to stop." -ForegroundColor Cyan

    while ($true) {
        foreach ($box in $Boxes) {
            $isUp = (Get-BoxState -Box $box) -ne "Down"
            $hadBeenUp = [bool]$wasUp[$box]

            if ($isUp) {
                $downCount[$box] = 0
            } else {
                $downCount[$box] = [int]$downCount[$box] + 1
            }

            $confirmedDown = (-not $isUp) -and ([int]$downCount[$box] -ge $DownConfirmChecks)

            if ($hadBeenUp -and $confirmedDown) {
                $text = "Sandbox window '$box' was closed."
                Write-Host $text -ForegroundColor Red
                Show-WindowsToastNotification -Title $ToastTitle -Message $text
                $wasUp[$box] = $false
                continue
            }

            if ($isUp) { $wasUp[$box] = $true }
        }

        Start-Sleep -Seconds $PollSec
    }
}

if ($MonitorDetached) {
    if (-not $IsWindows) { exit 1 }
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
        exit 1
    }
    $cfgDetached = Import-PowerShellDataFile -Path $ConfigPath
    $boxesDetached = @($cfgDetached.Boxes)
    $pollDetached = [int]$cfgDetached.MonitorPollSec
    $downChDetached = [Math]::Max(1, [int]$cfgDetached.MonitorDownConfirmChecks)
    $toastDetached = [string]$cfgDetached.MonitorToastTitle
    Start-WindowCloseMonitor -Boxes $boxesDetached -PollSec $pollDetached -DownConfirmChecks $downChDetached -ToastTitle $toastDetached
    exit 0
}

if (($PSVersionTable.PSEdition -eq 'Core') -and (-not $IsWindows)) {
    Write-Host "This script requires Windows (Sandboxie-Plus)." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config not found, using embedded defaults: $ConfigPath" -ForegroundColor DarkYellow
    $cfg = Get-EmbeddedDefaultConfig
} else {
    $cfg = Import-PowerShellDataFile -Path $ConfigPath
}

$startExe = [string]$cfg.StartExe
$launcherExe = [string]$cfg.LauncherExe
$boxes = @($cfg.Boxes)
$skipCacheClearEff = if ($PSBoundParameters.ContainsKey('SkipCacheClear')) { [bool]$SkipCacheClear } else { [bool]$cfg.SkipCacheClear }

if ($LaunchDelaySec -ge 0) { $launchDelaySecEff = $LaunchDelaySec } else { $launchDelaySecEff = [int]$cfg.LaunchDelaySec }
if ($WaitForGameSec -ge 0) { $waitForGameSecEff = $WaitForGameSec } else { $waitForGameSecEff = [int]$cfg.WaitForGameSec }
if ($MaxRetriesPerBox -ge 0) { $maxRetriesEff = $MaxRetriesPerBox } else { $maxRetriesEff = [int]$cfg.MaxRetriesPerBox }

$stableSecEff = [int]$cfg.StableSec
$waitStartingTimeoutSec = if ($cfg.ContainsKey("WaitStartingTimeoutSec")) { [int]$cfg.WaitStartingTimeoutSec } else { 120 }
$waitStartingStableSec = if ($cfg.ContainsKey("WaitStartingStableSec")) { [int]$cfg.WaitStartingStableSec } else { 10 }

$enableCdnCheck = [bool]$cfg.EnableCdnCheck
$cfgUrl = [string]$cfg.CfgUrl
$cdnMaxAttempts = [int]$cfg.CdnMaxAttempts
$cdnDelaySec = [int]$cfg.CdnDelaySec
$dnsWarmupServer = [string]$cfg.DnsWarmupServer
$warmupDomains = @($cfg.WarmupDomains)

$monitorClosedWindows = [bool]$cfg.MonitorClosedWindows
$monitorPollSec = [int]$cfg.MonitorPollSec
$monitorDownConfirmChecks = [Math]::Max(1, [int]$cfg.MonitorDownConfirmChecks)
$monitorToastTitle = [string]$cfg.MonitorToastTitle
$monitorInBackgroundCfg = if ($cfg.ContainsKey("MonitorInBackground")) { [bool]$cfg.MonitorInBackground } else { $false }

$runArrangerCfg = if ($cfg.ContainsKey("RunArrangerAfterLaunch")) { [bool]$cfg.RunArrangerAfterLaunch } else { $false }
$arrangerPathCfg = if ($cfg.ContainsKey("ArrangerScriptPath")) { [string]$cfg.ArrangerScriptPath } else { "" }

$runArrangerEff = $runArrangerCfg
if ($RunArrangerAfterLaunch) { $runArrangerEff = $true }

$defaultArranger = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "share\Arranger") "Расставитель.ps1"
if (-not [string]::IsNullOrWhiteSpace($ArrangerScriptPath)) {
    $arrangerResolved = $ArrangerScriptPath
} elseif (-not [string]::IsNullOrWhiteSpace($arrangerPathCfg)) {
    $arrangerResolved = $arrangerPathCfg
} else {
    $arrangerResolved = $defaultArranger
}

if (-not (Test-Path -LiteralPath $startExe)) {
    Write-Host "Sandboxie Start.exe not found: $startExe" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $launcherExe)) {
    Write-Host "Game launcher not found: $launcherExe" -ForegroundColor Red
    exit 1
}
if ($boxes.Count -lt 1) {
    Write-Host "No boxes configured." -ForegroundColor Red
    exit 1
}

$runTerminateAll = ($cfg.SkipTerminate -ne $true)
if ($TerminateAllAtStart) { $runTerminateAll = $true }
if ($SkipTerminate) { $runTerminateAll = $false }

function Invoke-StartSingleBoxWithRetry {
    param(
        [string]$Box,
        [int]$Retries,
        [bool]$CdnPassed,
        [bool]$EnableCdn
    )

    for ($attempt = 1; $attempt -le ($Retries + 1); $attempt++) {
        if ($attempt -eq 1 -and $EnableCdn -and (-not $CdnPassed)) {
            Write-Host "CDN is unstable (pre-check). Starting anyway: $Box" -ForegroundColor Yellow
        }

        Write-Host "Start $Box (attempt $attempt/$($Retries + 1))..." -ForegroundColor Yellow
        & $startExe "/box:$Box" "$launcherExe" | Out-Null
        Start-Sleep -Seconds 3

        if (Wait-BoxReady -Box $Box -TimeoutSec $waitForGameSecEff -StableSec $stableSecEff) {
            Write-Host "$Box is ready in game (stable)." -ForegroundColor DarkGreen
            return $true
        }

        Write-Host "$Box did not reach stable game state in time." -ForegroundColor DarkYellow
        if ($attempt -le $Retries) {
            Write-Host "Restarting only $Box..." -ForegroundColor DarkYellow
            Stop-BoxProcesses -Box $Box -StartExePath $startExe
            Start-Sleep -Seconds $launchDelaySecEff
        }
    }

    return $false
}

Write-Host "Dragonhunter: start $($boxes.Count) sandbox window(s) | config=$ConfigPath" -ForegroundColor Cyan

if ($runTerminateAll) {
    Write-Host "Terminate all sandboxed programs (Start.exe /terminate_all)..." -ForegroundColor Yellow
    & $startExe /terminate_all | Out-Null
    Start-Sleep -Seconds 1
}

if (-not $skipCacheClearEff) {
    foreach ($box in $boxes) {
        $base = Get-SandboxCacheBase -LauncherExePath $launcherExe -BoxName $box
        if (-not $base) { continue }
        Remove-Item "$base\launcher\CefCache" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$base\game\ext" -Force -ErrorAction SilentlyContinue
    }
}

$cndWarmupOk = $true
if ($enableCdnCheck) {
    $cndWarmupOk = Wait-CdnReady -Url $cfgUrl -MaxAttempts $cdnMaxAttempts -DelaySec $cdnDelaySec
    if (-not $cndWarmupOk) {
        Write-Host "CDN check did not complete successfully; continuing with box startup." -ForegroundColor Yellow
    }
}

foreach ($domain in $warmupDomains) {
    try {
        Resolve-DnsName $domain -Type A -Server $dnsWarmupServer | Out-Null
    } catch {}
}

for ($i = 0; $i -lt $boxes.Count; $i++) {
    $box = $boxes[$i]
    $state = Get-BoxState -Box $box

    if ($state -eq "Ready") {
        Write-Host "$box is already running. Skip." -ForegroundColor DarkCyan
        continue
    }

    if ($state -eq "Starting") {
        Write-Host "$box is already starting. Waiting..." -ForegroundColor DarkCyan
        if (Wait-BoxReady -Box $box -TimeoutSec $waitStartingTimeoutSec -StableSec $waitStartingStableSec) {
            Write-Host "$box became ready. Skip restart." -ForegroundColor DarkCyan
            continue
        }

        Write-Host "$box looks stuck. Restarting only this box..." -ForegroundColor DarkYellow
        Stop-BoxProcesses -Box $box -StartExePath $startExe
        Start-Sleep -Seconds 3
    }

    if ($state -eq "Down") {
        Stop-BoxProcesses -Box $box -StartExePath $startExe
        Start-Sleep -Seconds 2
    }

    $ok = Invoke-StartSingleBoxWithRetry -Box $box -Retries $maxRetriesEff -CdnPassed $cndWarmupOk -EnableCdn $enableCdnCheck
    if (-not $ok) {
        Write-Host "Stop sequence: $box failed. Fix this box and rerun script." -ForegroundColor Red
        exit 1
    }

    Start-Sleep -Seconds 5
}

Write-Host "Done. All windows started." -ForegroundColor Green

if ($runArrangerEff -and (Test-Path -LiteralPath $arrangerResolved)) {
    Write-Host "Running Arranger once: $arrangerResolved" -ForegroundColor Cyan
    $arrProc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$arrangerResolved`"",
        "-Once"
    ) -PassThru -Wait
    Write-Host "Arranger exit code: $($arrProc.ExitCode)" -ForegroundColor DarkGray
} elseif ($runArrangerEff) {
    Write-Host "Arranger skipped (script not found): $arrangerResolved" -ForegroundColor Yellow
}

$startMonitorBg = $monitorInBackgroundCfg -and $monitorClosedWindows -and (Test-Path -LiteralPath $ConfigPath)

if ($monitorClosedWindows) {
    if ($monitorInBackgroundCfg -and -not $startMonitorBg) {
        Write-Host "MonitorInBackground требует существующий файл конфигурации ($ConfigPath); монитор будет в этом окне." -ForegroundColor Yellow
    }
    if ($startMonitorBg) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
            "-File", "`"$PSCommandPath`"",
            "-MonitorDetached",
            "-ConfigPath", "`"$ConfigPath`""
        ) | Out-Null
        Write-Host "Close-monitor started in background (hidden PowerShell)." -ForegroundColor DarkCyan
    } else {
        Start-WindowCloseMonitor -Boxes $boxes -PollSec $monitorPollSec `
            -DownConfirmChecks $monitorDownConfirmChecks -ToastTitle $monitorToastTitle
    }
}
