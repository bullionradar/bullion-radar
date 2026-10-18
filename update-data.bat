@echo off
rem Double-click this file to download the latest data and update the site.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-data.ps1"
pause
