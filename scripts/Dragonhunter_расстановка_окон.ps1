param(
    [int]$WaitForGameSec = 120
)

$ErrorActionPreference = "SilentlyContinue"
$boxes = @("1Atarun", "2Emilian", "3Ceres")
$boxGameHandles = @{}

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinApi {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}
"@

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

function Get-AllGameWindows {
    return Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -like "pc_lyzs_ru_rel_*" -and
            $_.MainWindowHandle -ne 0
        } |
        Sort-Object StartTime |
        Select-Object ProcessName, Id, MainWindowHandle, MainWindowTitle, StartTime
}

function Arrange-GameWindows {
    $work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $left = $bounds.Left
    $top = $work.Top
    $width = $bounds.Width

    $layout = @("1Atarun", "2Emilian", "3Ceres")

    $allGameWindows = @(Get-AllGameWindows)
    $usedHandles = @{}
    $handlesByBox = @{}

    foreach ($box in $layout) {
        $hWnd = 0

        if ($boxGameHandles.ContainsKey($box)) {
            $hWnd = [int64]$boxGameHandles[$box]
        }

        if ($hWnd -eq 0) {
            $hWnd = Get-GameWindowHandle -Box $box
        }

        if ($hWnd -eq 0) {
            $candidate = $allGameWindows |
                Where-Object { -not $usedHandles.ContainsKey([string]$_.MainWindowHandle) } |
                Select-Object -First 1
            if ($candidate) {
                $hWnd = [int64]$candidate.MainWindowHandle
            }
        }

        if ($hWnd -ne 0) {
            $handlesByBox[$box] = [int64]$hWnd
            $usedHandles[[string]$hWnd] = $true
        }
    }

    $orderRightToLeft = @("3Ceres", "2Emilian", "1Atarun")
    $screenRight = $left + $width
    $rightNudgePx = 8
    $targetRight = $screenRight + $rightNudgePx
    $cursorRight = $targetRight
    $placed = @{}
    $visualOverlapPx = 14

    foreach ($box in $orderRightToLeft) {
        if (-not $handlesByBox.ContainsKey($box)) { continue }

        $hWnd = [IntPtr]$handlesByBox[$box]
        [WinApi]::ShowWindowAsync($hWnd, 9) | Out-Null

        $rect = New-Object WinApi+RECT
        if (-not [WinApi]::GetWindowRect($hWnd, [ref]$rect)) { continue }

        $w = [Math]::Max(300, $rect.Right - $rect.Left)
        $h = [Math]::Max(500, $rect.Bottom - $rect.Top)
        $x = $cursorRight - $w
        $y = $top

        [WinApi]::MoveWindow($hWnd, $x, $y, $w, $h, $true) | Out-Null
        $placed[$box] = [IntPtr]$hWnd
        $cursorRight = $x + $visualOverlapPx
    }

    if ($placed.ContainsKey("3Ceres")) {
        $ceresRect = New-Object WinApi+RECT
        if ([WinApi]::GetWindowRect($placed["3Ceres"], [ref]$ceresRect)) {
            $dx = $targetRight - $ceresRect.Right
            if ($dx -ne 0) {
                foreach ($box in $orderRightToLeft) {
                    if (-not $placed.ContainsKey($box)) { continue }
                    $rect = New-Object WinApi+RECT
                    $hWnd = $placed[$box]
                    if (-not [WinApi]::GetWindowRect($hWnd, [ref]$rect)) { continue }
                    $w = [Math]::Max(300, $rect.Right - $rect.Left)
                    $h = [Math]::Max(500, $rect.Bottom - $rect.Top)
                    [WinApi]::MoveWindow($hWnd, $rect.Left + $dx, $rect.Top, $w, $h, $true) | Out-Null
                }
            }
        }
    }
}

Write-Host "Arrange: waiting for game windows..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($WaitForGameSec)
while ((Get-Date) -lt $deadline) {
    $detected = @(Get-AllGameWindows)
    if ($detected.Count -ge 3) {
        foreach ($box in $boxes) {
            $hWnd = Get-GameWindowHandle -Box $box
            if ($hWnd -ne 0) {
                $boxGameHandles[$box] = [int64]$hWnd
            }
        }

        Arrange-GameWindows
        Write-Host "Done. Windows arranged: left Atarun | middle Emilian | right Ceres." -ForegroundColor Green
        exit 0
    }

    Start-Sleep -Seconds 3
}

Write-Host "Done. Arrange skipped: less than 3 game windows detected." -ForegroundColor Yellow
