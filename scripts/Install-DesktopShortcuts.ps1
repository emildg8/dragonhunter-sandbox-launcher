param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

if (-not (($PSVersionTable.PSEdition -eq "Desktop") -or (($PSVersionTable.PSEdition -eq "Core") -and $IsWindows))) {
    Write-Host "Только Windows." -ForegroundColor Red
    exit 1
}

function Normalize-PathStr {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try {
        return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path)
    } catch {
        try {
            return [System.IO.Path]::GetFullPath($Path)
        } catch {
            return $Path.Trim().ToLowerInvariant()
        }
    }
}

function Install-OneShortcut {
    param(
        [string]$Desktop,
        $Shell,
        [string]$ShortcutPath,
        [string]$TargetCmd,
        [string]$WorkingDir,
        [string]$Description,
        [switch]$WhatIf
    )

    $canonical = Normalize-PathStr $TargetCmd
    $removed = @()
    foreach ($f in Get-ChildItem -LiteralPath $Desktop -Filter "*.lnk" -ErrorAction SilentlyContinue) {
        try {
            $sc = $Shell.CreateShortcut($f.FullName)
            $t = Normalize-PathStr $sc.TargetPath
            if ($t -and $t -eq $canonical -and $f.FullName -ne $ShortcutPath) {
                if ($WhatIf) {
                    Write-Host "[WhatIf] Удалить дубликат: $($f.Name)" -ForegroundColor DarkYellow
                } else {
                    Remove-Item -LiteralPath $f.FullName -Force
                    $removed += $f.Name
                }
            }
        } catch {}
    }
    if ($removed.Count -gt 0) {
        Write-Host "Удалены дубликаты для $(Split-Path -Leaf $ShortcutPath): $($removed -join ', ')" -ForegroundColor DarkCyan
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] $ShortcutPath -> $TargetCmd" -ForegroundColor DarkYellow
        return
    }

    $n = $Shell.CreateShortcut($ShortcutPath)
    $n.TargetPath = $TargetCmd
    $n.WorkingDirectory = $WorkingDir
    $n.Description = $Description
    $n.IconLocation = "$env:SystemRoot\System32\shell32.dll,259"
    $n.Save()
    Write-Host "Готово: $ShortcutPath" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$launcherCmd = Join-Path $repoRoot "share\Launcher\Запускатор.cmd"
$arrangerCmd = Join-Path $repoRoot "share\Arranger\Расставитель.cmd"

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
if (-not (Test-Path -LiteralPath $desktop)) {
    Write-Host "Не найдена папка рабочего стола." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $launcherCmd)) {
    Write-Host "Нет файла (клонируйте share/Launcher): $launcherCmd" -ForegroundColor Yellow
}
if (-not (Test-Path -LiteralPath $arrangerCmd)) {
    Write-Host "Нет файла (клонируйте share/Arranger): $arrangerCmd" -ForegroundColor Yellow
}

if ((Test-Path -LiteralPath $launcherCmd)) {
    $lnk = Join-Path $desktop "Запускатор.lnk"
    Install-OneShortcut -Desktop $desktop -Shell $shell -ShortcutPath $lnk -TargetCmd $launcherCmd `
        -WorkingDir (Split-Path -Parent $launcherCmd) -Description "Dragon Hunter — Запускатор (Sandboxie-Plus)" -WhatIf:$WhatIf
}

if ((Test-Path -LiteralPath $arrangerCmd)) {
    $lnk = Join-Path $desktop "Расставитель.lnk"
    Install-OneShortcut -Desktop $desktop -Shell $shell -ShortcutPath $lnk -TargetCmd $arrangerCmd `
        -WorkingDir (Split-Path -Parent $arrangerCmd) -Description "Dragon Hunter — Расставитель окон" -WhatIf:$WhatIf
}
