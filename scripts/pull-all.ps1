# Pull latest for all DCS-related git repositories (packages monorepo + sibling app).
#
# Usage:
#   .\scripts\pull-all.ps1
#
# Optional environment overrides:
#   $env:DCS_PACKAGES_DIR = "E:\path\to\dcs-packages"
#   $env:DCS_APP_DIR = "E:\path\to\dcs"
#   $env:DCS_GIT_BRANCH = "main"

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackagesDir = if ($env:DCS_PACKAGES_DIR) { $env:DCS_PACKAGES_DIR } else { Split-Path -Parent $ScriptDir }
$AppDir = if ($env:DCS_APP_DIR) { $env:DCS_APP_DIR } else { Join-Path (Split-Path -Parent $PackagesDir) "dcs" }
$PreferredBranch = if ($env:DCS_GIT_BRANCH) { $env:DCS_GIT_BRANCH } else { "" }

function Pull-Repo {
    param(
        [string]$Dir,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Dir)) {
        Write-Host "[skip] $Name - directory not found: $Dir"
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Dir ".git"))) {
        Write-Host "[skip] $Name - not a git repository: $Dir"
        return
    }

    Write-Host ""
    Write-Host "=== $Name ($Dir) ==="
    Push-Location -LiteralPath $Dir

    try {
        $currentBranch = git rev-parse --abbrev-ref HEAD
        if ($currentBranch -eq "HEAD") {
            throw "Detached HEAD - checkout a branch before pulling."
        }

        if (-not [string]::IsNullOrWhiteSpace($PreferredBranch) -and $currentBranch -ne $PreferredBranch) {
            Write-Host "Current branch is $currentBranch (preferred: $PreferredBranch)."
        }

        Write-Host "Fetching origin..."
        git fetch origin

        Write-Host "Pulling origin/$currentBranch..."
        git pull --ff-only origin $currentBranch

        if ((Test-Path -LiteralPath "melos.yaml") -and (Get-Command melos -ErrorAction SilentlyContinue)) {
            Write-Host "Running melos bootstrap..."
            try { melos bootstrap } catch { Write-Host "melos bootstrap failed (continuing)" }
        }

        if ((Test-Path -LiteralPath "pubspec.yaml") -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
            $pubspec = Get-Content -LiteralPath "pubspec.yaml" -Raw
            if ($pubspec -match "(?m)^flutter:") {
                Write-Host "Running flutter pub get..."
                try { flutter pub get } catch { Write-Host "flutter pub get failed (continuing)" }
            }
        }

        Write-Host "Done: $Name"
    } finally {
        Pop-Location
    }
}

Write-Host "DCS pull-all"
Write-Host "Packages: $PackagesDir"
Write-Host "App:      $AppDir"

Pull-Repo -Dir $PackagesDir -Name "dcs-packages"
Pull-Repo -Dir $AppDir -Name "dcs"

Write-Host ""
Write-Host "All repositories pulled."
