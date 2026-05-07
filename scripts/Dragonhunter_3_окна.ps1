param(
    [switch]$SkipTerminate,
    [switch]$SkipCacheClear,
    [int]$LaunchDelaySec = 60,
    [int]$WaitForGameSec = 900,
    [int]$MaxRetriesPerBox = 1
)

$ErrorActionPreference = "SilentlyContinue"

$startExe = "C:\Program Files\Sandboxie-Plus\Start.exe"
$launcherExe = "D:\4399\slsmru\launcher\Dragon_hunter.exe"
$boxes = @("1Atarun", "2Emilian", "3Ceres")
$warmupDomains = @(
    "lyzs-cdnres.4399ru.com",
    "pc.4399sy.ru",
    "mkts.4399sy.ru",
    "y.4399sy.ru"
)
$cfgUrl = "https://lyzs-cdnres.4399ru.com/RU/stable/mix_ru/up/pc_exe/cfg.xml"

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
    param(
        [int]$MaxAttempts = 6,
        [int]$DelaySec = 10
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $cfgUrl -Method Head -TimeoutSec 15 -UseBasicParsing
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
                Write-Host "CDN check OK (attempt $attempt)." -ForegroundColor DarkGreen
                return $true
            }
        } catch {
        }

        Write-Host "CDN check failed (attempt $attempt/$MaxAttempts), retry in $DelaySec sec..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $DelaySec
    }

    return $false
}

function Wait-BoxReady {
    param(
        [string]$Box,
        [int]$TimeoutSec = 900,
        [int]$StableSec = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $stableSince = $null

    while ((Get-Date) -lt $deadline) {
        $gameHwnd = Get-GameWindowHandle -Box $Box
        $launcherHwnd = Get-LauncherWindowHandle -Box $Box

        if ($gameHwnd -ne 0 -and $launcherHwnd -eq 0) {
            if (-not $stableSince) {
                $stableSince = Get-Date
            }

            $stableFor = ((Get-Date) - $stableSince).TotalSeconds
            if ($stableFor -ge $StableSec) {
                return $true
            }
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

    if ($gameHwnd -ne 0 -and $launcherHwnd -eq 0) { return "Ready" }
    if ($gameHwnd -ne 0 -or $launcherHwnd -ne 0) { return "Starting" }
    return "Down"
}

function Start-BoxWithRetry {
    param(
        [string]$Box,
        [int]$Retries = 1
    )

    for ($attempt = 1; $attempt -le ($Retries + 1); $attempt++) {
        if (-not (Wait-CdnReady)) {
            Write-Host "CDN is unstable now. Starting anyway: $Box" -ForegroundColor Yellow
        }

        Write-Host "Start $Box (attempt $attempt/$($Retries + 1))..." -ForegroundColor Yellow
        & $startExe "/box:$Box" "$launcherExe" | Out-Null
        Start-Sleep -Seconds 3

        if (Wait-BoxReady -Box $Box -TimeoutSec $WaitForGameSec) {
            Write-Host "$Box is ready in game (stable)." -ForegroundColor DarkGreen
            return $true
        }

        Write-Host "$Box did not reach stable game state in time." -ForegroundColor DarkYellow
        if ($attempt -le $Retries) {
            Write-Host "Restarting only $Box..." -ForegroundColor DarkYellow
            Stop-BoxProcesses -Box $Box
            Start-Sleep -Seconds $LaunchDelaySec
        }
    }

    return $false
}

Write-Host "Dragonhunter launcher: start 3 sandboxes" -ForegroundColor Cyan

if (-not $SkipTerminate) {
    & $startExe /terminate_all | Out-Null
    Start-Sleep -Seconds 1
}

if (-not $SkipCacheClear) {
    foreach ($box in $boxes) {
        $base = "C:\Sandbox\emildg8\$box\drive\D\4399\slsmru"
        Remove-Item "$base\launcher\CefCache" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$base\game\ext" -Force -ErrorAction SilentlyContinue
    }
}

foreach ($domain in $warmupDomains) {
    Resolve-DnsName $domain -Type A -Server 9.9.9.9 | Out-Null
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
        if (Wait-BoxReady -Box $box -TimeoutSec 120 -StableSec 10) {
            Write-Host "$box became ready. Skip restart." -ForegroundColor DarkCyan
            continue
        }

        Write-Host "$box looks stuck. Restarting only this box..." -ForegroundColor DarkYellow
        Stop-BoxProcesses -Box $box
        Start-Sleep -Seconds 3
    }

    if ($state -eq "Down") {
        # Clear possible hidden/zombie launcher processes in this box before fresh start.
        Stop-BoxProcesses -Box $box
        Start-Sleep -Seconds 2
    }

    $ok = Start-BoxWithRetry -Box $box -Retries $MaxRetriesPerBox
    if (-not $ok) {
        Write-Host "Stop sequence: $box failed. Fix this box and rerun script." -ForegroundColor Red
        exit 1
    }

    Start-Sleep -Seconds 5
}

Write-Host "Done. All windows started. Arrange script is separate now." -ForegroundColor Green
