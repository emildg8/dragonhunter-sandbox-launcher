@{
    # Windows only (Sandboxie-Plus)
    StartExe = "C:\Program Files\Sandboxie-Plus\Start.exe"
    LauncherExe = "D:\4399\slsmru\launcher\Dragon_hunter.exe"

    # Any amount of sandbox names in desired startup order
    Boxes = @("1Atarun", "2Emilian", "3Ceres")

    # Start behavior
    SkipTerminate = $true
    SkipCacheClear = $true
    LaunchDelaySec = 60
    WaitForGameSec = 900
    StableSec = 20
    MaxRetriesPerBox = 1

    # Optional CDN pre-check (safe for users without AdGuard)
    EnableCdnCheck = $true
    CfgUrl = "https://lyzs-cdnres.4399ru.com/RU/stable/mix_ru/up/pc_exe/cfg.xml"
    CdnMaxAttempts = 6
    CdnDelaySec = 10
    DnsWarmupServer = "9.9.9.9"
    WarmupDomains = @(
        "lyzs-cdnres.4399ru.com",
        "pc.4399sy.ru",
        "mkts.4399sy.ru",
        "y.4399sy.ru"
    )

    # Arrange behavior
    ArrangeWaitForGameSec = 120
    RightNudgePx = 8
    VisualOverlapPx = 14

    # Close-monitor behavior (toast + sound)
    MonitorClosedWindows = $true
    MonitorPollSec = 5
    MonitorDownConfirmChecks = 5
    MonitorToastTitle = "Dragonhunter Monitor"
}
