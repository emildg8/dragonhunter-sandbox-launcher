@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start_Sandbox_Game.ps1" -ConfigPath "%~dp0sandbox-launcher.config.psd1"
pause
