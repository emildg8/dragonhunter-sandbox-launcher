@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Arrange_Sandbox_Windows.ps1" -ConfigPath "%~dp0sandbox-launcher.config.psd1"
pause
