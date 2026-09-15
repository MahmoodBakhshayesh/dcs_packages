@echo off
REM Pull latest for dcs-packages + sibling dcs using Git Bash (not WSL).
setlocal
set "SCRIPT_DIR=%~dp0"
set "GIT_BASH="
if exist "C:\Program Files\Git\bin\bash.exe" set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"
if exist "C:\Program Files (x86)\Git\bin\bash.exe" set "GIT_BASH=C:\Program Files (x86)\Git\bin\bash.exe"
if "%GIT_BASH%"=="" (
  echo Git Bash not found. Use: powershell -File "%SCRIPT_DIR%pull-all.ps1"
  exit /b 1
)
"%GIT_BASH%" "%SCRIPT_DIR%pull-all.sh" %*
endlocal
