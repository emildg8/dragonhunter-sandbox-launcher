param(
    [string]$ConfigPath = "$PSScriptRoot\sandbox-launcher.config.psd1"
)

$ErrorActionPreference = "SilentlyContinue"

#region Host & config load

function Test-SbWindowsHost {
    if ($PSVersionTable.PSEdition -eq "Desktop") { return $true }
    return $IsWindows -eq $true
}

if (-not (Test-SbWindowsHost)) {
    Write-Host "This launcher works on Windows only (Sandboxie-Plus)." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$cfg = Import-PowerShellDataFile -Path $ConfigPath

$startExe = [string]$cfg.StartExe
$launcherExe = [string]$cfg.LauncherExe
$boxes = @($cfg.Boxes)
$skipTerminate = [bool]$cfg.SkipTerminate
$skipCacheClear = [bool]$cfg.SkipCacheClear
$launchDelaySec = [int]$cfg.LaunchDelaySec
$waitForGameSec = [int]$cfg.WaitForGameSec
$stableSec = [int]$cfg.StableSec
$maxRetriesPerBox = [int]$cfg.MaxRetriesPerBox
$enableCdnCheck = [bool]$cfg.EnableCdnCheck
$cfgUrl = [string]$cfg.CfgUrl
$cdnMaxAttempts = [int]$cfg.CdnMaxAttempts
$cdnDelaySec = [int]$cfg.CdnDelaySec
$dnsWarmupServer = [string]$cfg.DnsWarmupServer
$warmupDomains = @($cfg.WarmupDomains)
$monitorClosedWindows = [bool]$cfg.MonitorClosedWindows
$monitorPollSec = [int]$cfg.MonitorPollSec
$monitorToastTitle = [string]$cfg.MonitorToastTitle
$monitorDownConfirmChecks = [Math]::Max(1, [int]$cfg.MonitorDownConfirmChecks)

if (-not (Test-Path -LiteralPath $startExe)) {
    Write-Host "Sandboxie Start.exe not found: $startExe" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $launcherExe)) {
    Write-Host "Game launcher not found: $launcherExe" -ForegroundColor Red
    exit 1
}
if ($boxes.Count -lt 1) {
    Write-Host "No boxes configured in config file." -ForegroundColor Red
    exit 1
}

#endregion

#region Window / box helpers

function Escape-XmlText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return ($Text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;").Replace("'", "&apos;"))
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
    if (-not $enableCdnCheck) { return $true }
    for ($attempt = 1; $attempt -le $cdnMaxAttempts; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $cfgUrl -Method Head -TimeoutSec 15 -UseBasicParsing
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) { return $true }
        } catch {}
        Write-Host "CDN check failed ($attempt/$cdnMaxAttempts), retry in $cdnDelaySec sec..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $cdnDelaySec
    }
    return $false
}

function Wait-BoxReady {
    param([string]$Box)
    $deadline = (Get-Date).AddSeconds($waitForGameSec)
    $stableSince = $null
    while ((Get-Date) -lt $deadline) {
        $gameHwnd = Get-GameWindowHandle -Box $Box
        $launcherHwnd = Get-LauncherWindowHandle -Box $Box
        if ($gameHwnd -ne [IntPtr]::Zero -and $launcherHwnd -eq [IntPtr]::Zero) {
            if (-not $stableSince) { $stableSince = Get-Date }
            if (((Get-Date) - $stableSince).TotalSeconds -ge $stableSec) { return $true }
        } else {
            $stableSince = $null
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Stop-BoxProcesses {
    param([string]$Box)
    & $startExe "/box:$Box" /terminate | Out-Null
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

function Start-BoxWithRetry {
    param([string]$Box, [bool]$CdnPassedPreCheck)
    for ($attempt = 1; $attempt -le ($maxRetriesPerBox + 1); $attempt++) {
        if ($attempt -eq 1 -and $enableCdnCheck -and (-not $CdnPassedPreCheck)) {
            Write-Host "CDN unstable (pre-check). Starting anyway: $Box" -ForegroundColor Yellow
        }
        Write-Host "Start $Box (attempt $attempt/$($maxRetriesPerBox + 1))..." -ForegroundColor Yellow
        & $startExe "/box:$Box" "$launcherExe" | Out-Null
        Start-Sleep -Seconds 3
        if (Wait-BoxReady -Box $Box) {
            Write-Host "$Box is ready in game." -ForegroundColor DarkGreen
            return $true
        }
        if ($attempt -le $maxRetriesPerBox) {
            Write-Host "Restarting only $Box..." -ForegroundColor DarkYellow
            Stop-BoxProcesses -Box $Box
            Start-Sleep -Seconds $launchDelaySec
        }
    }
    return $false
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

#endregion

#region Main

Write-Host "Sandbox launcher: start $($boxes.Count) windows" -ForegroundColor Cyan

if (-not $skipTerminate) {
    & $startExe /terminate_all | Out-Null
    Start-Sleep -Seconds 1
}

if (-not $skipCacheClear) {
    foreach ($box in $boxes) {
        $launcherDir = Split-Path -Path $launcherExe -Parent
        $slsmruBase = Split-Path -Path $launcherDir -Parent
        $drivePath = $slsmruBase.Substring(0, 1) + $slsmruBase.Substring(2)
        $base = "C:\Sandbox\$env:USERNAME\$box\drive\$drivePath"
        Remove-Item "$base\launcher\CefCache" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$base\game\ext" -Force -ErrorAction SilentlyContinue
    }
}

foreach ($domain in $warmupDomains) {
    try {
        Resolve-DnsName $domain -Type A -Server $dnsWarmupServer | Out-Null
    } catch {}
}

$cdnWarmupOk = $true
if ($enableCdnCheck) {
    $cdnWarmupOk = Wait-CdnReady
    if (-not $cdnWarmupOk) {
        Write-Host "CDN check did not complete successfully; continuing with box startup." -ForegroundColor Yellow
    }
}

foreach ($box in $boxes) {
    $state = Get-BoxState -Box $box

    if ($state -eq "Ready") {
        Write-Host "$box is already running. Skip." -ForegroundColor DarkCyan
        continue
    }

    if ($state -eq "Starting") {
        Write-Host "$box is already starting. Waiting..." -ForegroundColor DarkCyan
        if (Wait-BoxReady -Box $box) {
            Write-Host "$box became ready. Skip restart." -ForegroundColor DarkCyan
            continue
        }
        Write-Host "$box looks stuck. Restarting only this box..." -ForegroundColor DarkYellow
        Stop-BoxProcesses -Box $box
        Start-Sleep -Seconds 3
    }

    if ($state -eq "Down") {
        Stop-BoxProcesses -Box $box
        Start-Sleep -Seconds 2
    }

    $ok = Start-BoxWithRetry -Box $box -CdnPassedPreCheck $cdnWarmupOk
    if (-not $ok) {
        Write-Host "Stop sequence: $box failed. Fix this box and rerun." -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 5
}

Write-Host "Done. All configured windows started." -ForegroundColor Green

if ($monitorClosedWindows) {
    Start-WindowCloseMonitor -Boxes $boxes -PollSec $monitorPollSec `
        -DownConfirmChecks $monitorDownConfirmChecks -ToastTitle $monitorToastTitle
}

#endregion
