@{
    # Sandboxie-Plus + Dragon Hunter (локальный сценарий «три окна», см. Dragonhunter_3_окна.ps1)
    StartExe            = "C:\Program Files\Sandboxie-Plus\Start.exe"
    LauncherExe         = "D:\4399\slsmru\launcher\Dragon_hunter.exe"
    Boxes               = @("1Atarun", "2Emilian", "3Ceres")

    SkipTerminate       = $true
    SkipCacheClear      = $true
    LaunchDelaySec      = 60
    WaitForGameSec      = 900
    StableSec           = 20
    MaxRetriesPerBox    = 1

    # Если бокс уже в состоянии «Starting», сколько ждать стабильной игры перед перезапуском
    WaitStartingTimeoutSec = 120
    WaitStartingStableSec  = 10

    EnableCdnCheck      = $true
    CfgUrl              = "https://lyzs-cdnres.4399ru.com/RU/stable/mix_ru/up/pc_exe/cfg.xml"
    CdnMaxAttempts      = 6
    CdnDelaySec         = 10
    DnsWarmupServer     = "9.9.9.9"
    WarmupDomains       = @(
        "lyzs-cdnres.4399ru.com",
        "pc.4399sy.ru",
        "mkts.4399sy.ru",
        "y.4399sy.ru"
    )

    MonitorClosedWindows    = $true
    MonitorPollSec          = 5
    MonitorDownConfirmChecks = 5
    MonitorToastTitle       = "Dragonhunter Monitor"
    # После успешного старта не блокировать консоль (отдельное скрытое окно PowerShell)
    MonitorInBackground     = $false

    # Один вызов Расставителя (путь по умолчанию: ..\share\Arranger\Расставитель.ps1 от папки scripts)
    RunArrangerAfterLaunch = $false
    ArrangerScriptPath     = ""
}
