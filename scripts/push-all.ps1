# Push all DCS-related git repositories (packages monorepo + sibling app).
#
# Usage:
#   .\scripts\push-all.ps1 "your commit message"
#   .\scripts\push-all.ps1
#
# Optional environment overrides:
#   $env:DCS_PACKAGES_DIR = "E:\path\to\dcs-packages"
#   $env:DCS_APP_DIR = "E:\path\to\dcs"
#   $env:DCS_GIT_BRANCH = "main"

param(
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "chore: sync DCS projects $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackagesDir = if ($env:DCS_PACKAGES_DIR) { $env:DCS_PACKAGES_DIR } else { Split-Path -Parent $ScriptDir }
$AppDir = if ($env:DCS_APP_DIR) { $env:DCS_APP_DIR } else { Join-Path (Split-Path -Parent $PackagesDir) "dcs" }

function Push-Repo {
    param(
        [string]$Dir,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Dir)) {
        Write-Host "[skip] $Name — directory not found: $Dir"
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Dir ".git"))) {
        Write-Host "[skip] $Name — not a git repository: $Dir"
        return
    }

    Write-Host ""
    Write-Host "=== $Name ($Dir) ==="
    Push-Location -LiteralPath $Dir

    try {
        if ((Test-Path -LiteralPath "melos.yaml") -and (Get-Command melos -ErrorAction SilentlyContinue)) {
            Write-Host "Running melos bootstrap..."
            try {
                melos bootstrap
            } catch {
                Write-Host "melos bootstrap failed (continuing)"
            }
        }

        if ((Test-Path -LiteralPath "pubspec.yaml") -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
            $pubspec = Get-Content -LiteralPath "pubspec.yaml" -Raw
            if ($pubspec -match "(?m)^flutter:") {
                Write-Host "Running flutter pub get..."
                try {
                    flutter pub get
                } catch {
                    Write-Host "flutter pub get failed (continuing)"
                }
            }
        }

        $status = git status --porcelain
        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Host "No local changes to commit."
        } else {
            git add -A
            git commit -m $CommitMessage
            Write-Host "Committed changes."
        }

        $currentBranch = git rev-parse --abbrev-ref HEAD
        if ($currentBranch -eq "HEAD") {
            throw "Detached HEAD — cannot push branch. Checkout a branch first."
        }

        Write-Host "Pushing to origin/$currentBranch..."
        git push -u origin $currentBranch
        Write-Host "Done: $Name"
    } finally {
        Pop-Location
    }
}

Write-Host "DCS push-all"
Write-Host "Message: $CommitMessage"
Write-Host "Packages: $PackagesDir"
Write-Host "App:      $AppDir"

Push-Repo -Dir $PackagesDir -Name "dcs-packages"
Push-Repo -Dir $AppDir -Name "dcs"

Write-Host ""
Write-Host "All repositories processed."
