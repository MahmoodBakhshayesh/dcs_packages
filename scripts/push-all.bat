@echo off
setlocal

rem Run push-all.sh with Git Bash (not Windows WSL bash).
set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GIT_BASH%" set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not exist "%GIT_BASH%" (
  echo Git Bash not found. Install Git for Windows, or run:
  echo   powershell -ExecutionPolicy Bypass -File "%~dp0push-all.ps1" %*
  exit /b 1
)

"%GIT_BASH%" "%~dp0push-all.sh" %*
