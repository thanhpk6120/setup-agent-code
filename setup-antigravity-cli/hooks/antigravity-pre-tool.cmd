@echo off
setlocal
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0antigravity-pre-tool.ps1" %*
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%
exit /b 0
