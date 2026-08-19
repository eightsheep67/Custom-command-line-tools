@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -NoExit -File "%~dp0image2mp4.ps1"
pause