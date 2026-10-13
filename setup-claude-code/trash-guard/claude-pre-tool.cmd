@echo off
setlocal
node "%~dp0claude-pre-tool.js"
exit /b %ERRORLEVEL%
