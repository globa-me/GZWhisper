@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0package_windows_portable.ps1" %*
exit /b %errorlevel%
