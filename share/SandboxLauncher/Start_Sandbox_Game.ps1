param(
    [string]$ConfigPath = "$PSScriptRoot\sandbox-launcher.config.psd1"
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $IsWindows) {
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
    return 0
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
    return 0
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
        if ($gameHwnd -ne 0 -and $launcherHwnd -eq 0) {
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

function Start-BoxWithRetry {
    param([string]$Box)
    for ($attempt = 1; $attempt -le ($maxRetriesPerBox + 1); $attempt++) {
        if (-not (Wait-CdnReady)) {
            Write-Host "CDN unstable now. Starting anyway: $Box" -ForegroundColor Yellow
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

Write-Host "Sandbox launcher: start $($boxes.Count) windows" -ForegroundColor Cyan

if (-not $skipTerminate) {
    & $startExe /terminate_all | Out-Null
    Start-Sleep -Seconds 1
}

if (-not $skipCacheClear) {
    foreach ($box in $boxes) {
        $launcherDir = Split-Path -Path $launcherExe -Parent
        $slsmruBase = Split-Path -Path $launcherDir -Parent
        $drivePath = $slsmruBase.Substring(0,1) + $slsmruBase.Substring(2)
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

foreach ($box in $boxes) {
    $ok = Start-BoxWithRetry -Box $box
    if (-not $ok) {
        Write-Host "Stop sequence: $box failed. Fix this box and rerun." -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 5
}

Write-Host "Done. All configured windows started." -ForegroundColor Green
