param(
    [string]$ConfigPath = "$PSScriptRoot\sandbox-launcher.config.psd1"
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $IsWindows) {
    Write-Host "This arrange script works on Windows only." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$cfg = Import-PowerShellDataFile -Path $ConfigPath
$boxes = @($cfg.Boxes)
$waitForGameSec = [int]$cfg.ArrangeWaitForGameSec
$rightNudgePx = [int]$cfg.RightNudgePx
$visualOverlapPx = [int]$cfg.VisualOverlapPx
$boxGameHandles = @{}

if ($boxes.Count -lt 1) {
    Write-Host "No boxes configured in config file." -ForegroundColor Red
    exit 1
}

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

    $allGameWindows = @(Get-AllGameWindows)
    $usedHandles = @{}
    $handlesByBox = @{}

    foreach ($box in $boxes) {
        $hWnd = 0
        if ($boxGameHandles.ContainsKey($box)) { $hWnd = [int64]$boxGameHandles[$box] }
        if ($hWnd -eq 0) { $hWnd = Get-GameWindowHandle -Box $box }
        if ($hWnd -eq 0) {
            $candidate = $allGameWindows |
                Where-Object { -not $usedHandles.ContainsKey([string]$_.MainWindowHandle) } |
                Select-Object -First 1
            if ($candidate) { $hWnd = [int64]$candidate.MainWindowHandle }
        }
        if ($hWnd -ne 0) {
            $handlesByBox[$box] = [int64]$hWnd
            $usedHandles[[string]$hWnd] = $true
        }
    }

    $orderRightToLeft = @($boxes | Select-Object -Reverse)
    $targetRight = $left + $width + $rightNudgePx
    $cursorRight = $targetRight
    $placed = @{}

    foreach ($box in $orderRightToLeft) {
        if (-not $handlesByBox.ContainsKey($box)) { continue }
        $hWnd = [IntPtr]$handlesByBox[$box]
        [WinApi]::ShowWindowAsync($hWnd, 9) | Out-Null
        $rect = New-Object WinApi+RECT
        if (-not [WinApi]::GetWindowRect($hWnd, [ref]$rect)) { continue }
        $w = [Math]::Max(300, $rect.Right - $rect.Left)
        $h = [Math]::Max(500, $rect.Bottom - $rect.Top)
        $x = $cursorRight - $w
        [WinApi]::MoveWindow($hWnd, $x, $top, $w, $h, $true) | Out-Null
        $placed[$box] = [IntPtr]$hWnd
        $cursorRight = $x + $visualOverlapPx
    }

    $rightMostBox = $orderRightToLeft[0]
    if ($placed.ContainsKey($rightMostBox)) {
        $r = New-Object WinApi+RECT
        if ([WinApi]::GetWindowRect($placed[$rightMostBox], [ref]$r)) {
            $dx = $targetRight - $r.Right
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
$deadline = (Get-Date).AddSeconds($waitForGameSec)
while ((Get-Date) -lt $deadline) {
    $detected = @(Get-AllGameWindows)
    if ($detected.Count -ge $boxes.Count) {
        foreach ($box in $boxes) {
            $hWnd = Get-GameWindowHandle -Box $box
            if ($hWnd -ne 0) { $boxGameHandles[$box] = [int64]$hWnd }
        }
        Arrange-GameWindows
        Write-Host "Done. Windows arranged." -ForegroundColor Green
        exit 0
    }
    Start-Sleep -Seconds 3
}

Write-Host "Done. Arrange skipped: not enough game windows detected." -ForegroundColor Yellow
