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

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
if (-not (Test-Path -LiteralPath $desktop)) {
    Write-Host "Не найдена папка рабочего стола: $desktop" -ForegroundColor Red
    exit 1
}

$targetCmd = Join-Path $PSScriptRoot "Start_Sandbox_Game.cmd"
if (-not (Test-Path -LiteralPath $targetCmd)) {
    Write-Host "Не найден: $targetCmd" -ForegroundColor Red
    exit 1
}

$targetCanonical = Normalize-PathStr $targetCmd
$shortcutName = "Песочница Dragon Hunter.lnk"
$shortcutPath = Join-Path $desktop $shortcutName

$removed = @()
foreach ($f in Get-ChildItem -LiteralPath $desktop -Filter "*.lnk" -ErrorAction SilentlyContinue) {
    try {
        $sc = $shell.CreateShortcut($f.FullName)
        $t = Normalize-PathStr $sc.TargetPath
        if ($t -and $t -eq $targetCanonical -and $f.FullName -ne $shortcutPath) {
            if ($WhatIf) {
                Write-Host "[WhatIf] Удалить старый ярлык: $($f.Name)" -ForegroundColor DarkYellow
            } else {
                Remove-Item -LiteralPath $f.FullName -Force
                $removed += $f.Name
            }
        }
    } catch {}
}

if ($removed.Count -gt 0) {
    Write-Host "Удалены дубликаты (тот же .cmd): $($removed -join ', ')" -ForegroundColor DarkCyan
}

if ($WhatIf) {
    Write-Host "[WhatIf] Создать: $shortcutPath -> $targetCmd" -ForegroundColor DarkYellow
    exit 0
}

$newSc = $shell.CreateShortcut($shortcutPath)
$newSc.TargetPath = $targetCmd
$newSc.WorkingDirectory = $PSScriptRoot
$newSc.Description = "Dragon Hunter — старт окон Sandboxie (локальный скрипт)"
$newSc.IconLocation = "$env:SystemRoot\System32\shell32.dll,259"
$newSc.Save()

Write-Host "Готово: $shortcutPath" -ForegroundColor Green
