# deploy.ps1: Mirror Jeweled/ addon folder to WoW Forever AddOns directory.
# Usage: .\tools\deploy.ps1 [-Target "C:\...\AddOns\Jeweled"] [-Verify]

param(
    [string]$Target = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Jeweled",
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $RepoRoot "Jeweled"

if (-not (Test-Path $Source)) {
    throw "Source addon directory not found: $Source"
}

if ($Verify) {
    Write-Host "Running Lua 5.1 syntax checks and unit tests before deploy..." -ForegroundColor Cyan
    Get-ChildItem (Join-Path $Source "*.lua") | ForEach-Object {
        & luajit -bl $_.FullName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax error in $($_.Name)" }
    }
    & luajit (Join-Path $RepoRoot "tests\test_board.lua")
    if ($LASTEXITCODE -ne 0) { throw "test_board.lua failed" }
    $commsTest = Join-Path $RepoRoot "tests\test_comms.lua"
    if (Test-Path $commsTest) {
        & luajit $commsTest
        if ($LASTEXITCODE -ne 0) { throw "test_comms.lua failed" }
    }
}

$ParentDir = Split-Path -Parent $Target
if (-not (Test-Path $ParentDir)) {
    throw "WoW Forever AddOns directory not found: $ParentDir"
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null

# Robocopy /MIR mirrors cleanly (exit codes 0..7 indicate success)
$null = & robocopy $Source $Target /MIR /NFL /NDL /NJH /NJS /NC /NS
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

$count = (Get-ChildItem -Path $Target -Recurse -File).Count
Write-Host "Deployed Jeweled ($count files) -> $Target" -ForegroundColor Green
Write-Host "Run /reload in WoW Forever to load changes." -ForegroundColor DarkGray
