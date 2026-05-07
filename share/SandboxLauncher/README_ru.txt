Универсальный набор для запуска Dragonhunter через Sandboxie

1) Что внутри
- Start_Sandbox_Game.cmd / .ps1 : запуск окон по очереди с ожиданием готовности
- Arrange_Sandbox_Windows.cmd / .ps1 : отдельная расстановка окон
- sandbox-launcher.config.psd1 : настройки (пути, боксы, тайминги)

2) Быстрый старт
- Открой sandbox-launcher.config.psd1 в блокноте.
- Заполни:
  - StartExe (путь к Start.exe Sandboxie-Plus)
  - LauncherExe (путь к Dragon_hunter.exe)
  - Boxes (список боксов в нужном порядке)
- Запусти Start_Sandbox_Game.cmd
- После входа всех окон в игру запусти Arrange_Sandbox_Windows.cmd

3) Как изменить количество окон
- В Boxes укажи любое количество, например:
  Boxes = @("Box1", "Box2")
  или
  Boxes = @("Box1", "Box2", "Box3", "Box4", "Box5")
- Скрипт запуска и расстановки автоматически возьмет это количество.

4) Важно про ОС
- Скрипты работают только на Windows (PowerShell + Sandboxie-Plus + WinAPI окон).
- На Linux/macOS эти cmd/ps1 не применимы.

5) AdGuard не обязателен
- Скрипт не зависит от AdGuard.
- Если у пользователя нет AdGuard, ничего менять не нужно.
- При желании можно отключить CDN-проверку:
  EnableCdnCheck = $false

6) Полезные настройки
- SkipCacheClear = $true  -> сохранять логины
- MaxRetriesPerBox = 1    -> 1 повтор для проблемного бокса
- RightNudgePx / VisualOverlapPx -> микронастройка расстановки
