Dragonhunter_3_окна.ps1

Назначение: запуск нескольких клиентов в Sandboxie-Plus по списку боксов, опциональная очистка кэша лаунчера в песочнице, проверка CDN (один раз перед серией), монитор закрытия окон.

Конфигурация:
  По умолчанию читается dragonhunter-3-windows.config.psd1 рядом со скриптом.
  Если файла нет — используются встроенные значения (безопасный профиль: SkipTerminate=true).

Основные параметры командной строки:
  -ConfigPath "путь"     — другой .psd1
  -TerminateAllAtStart    — в начале выполнить Start.exe /terminate_all (осторожно)
  -SkipTerminate         — не завершать все процессы песочниц в начале (совместимость)
  -SkipCacheClear         — не чистить CefCache/game\ext
  -RunArrangerAfterLaunch — после успеха запустить Расставитель.ps1 -Once (путь в конфиге или ..\share\Arranger\)
  -MonitorDetached       — служебный режим: только монитор (вызывается скрытым процессом при MonitorInBackground=true)

MonitorInBackground в конфиге: отдельное окно PowerShell для монитора; нужен реальный файл конфигурации на диске по ConfigPath.

Полный Запускатор и Расставитель с дополнительными функциями — в отдельных репозиториях GitHub (docs/GITHUB_REPOS_ru.txt).
